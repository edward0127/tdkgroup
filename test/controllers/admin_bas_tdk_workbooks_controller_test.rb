require "test_helper"
require "stringio"
require_relative "../support/tdk_workbook_helper"

class AdminBasTdkWorkbooksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include TdkWorkbookHelper

  setup do
    login_as_admin
    clear_enqueued_jobs
    clear_performed_jobs
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "admin can queue process edit prepare download and reupload workbook" do
    client = create_client

    assert_difference "BasJob.count", 1 do
      post admin_bas_jobs_path, params: {
        bas_job: job_params(bas_client_id: client.id, workflow_type: "tdk_group")
      }
    end

    job = BasJob.last
    assert_redirected_to admin_bas_job_path(job)
    assert_equal "tdk_group", job.workflow_type

    get admin_bas_job_path(job)

    assert_response :success
    assert_select "h1", "Synthetic TDK Workflow Client Pty Ltd"
    assert_select ".tdk-workflow-hero .tdk-workflow-hero-actions" do
      assert_select "a", "Edit job"
      assert_select "a", "Back to BAS"
    end
    assert_select "h2", "Step 1 — Bank statement review"
    assert_select "strong", "Bank statement review"
    assert_select "h2", "Bank statement upload"
    assert_select "h2", "Background bank statement status"
    assert_select "h2", text: "Current active bank statement", count: 0
    assert_select "h3", text: "Current active statement", count: 0
    assert_includes response.body, "Upload a bank statement Excel or PDF for review."
    assert_includes response.body, "scanned PDFs can be processed when local OCR is available"
    assert_includes response.body, "download the latest Excel for bulk edits"
    refute_includes response.body, "Only XLSX files are supported. A successful upload becomes the active bank statement version"
    assert_select ".tdk-statement-action-row .tdk-upload-form"
    assert_select ".tdk-statement-action-row .tdk-export-action-slot"
    assert_not_includes response.body, "Bank workbook review"
    assert_select "input[type='file'][name='tdk_workbook[file]'][accept='.xlsx,.pdf,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/pdf']"
    assert_select "button", text: "Upload statement"

    assert_no_difference "BasBankTransaction.count" do
      assert_difference "BasTdkWorkbook.count", 1 do
        assert_enqueued_with(job: BasTdkWorkbookProcessingJob) do
          post admin_bas_job_tdk_workbooks_path(job), params: {
            tdk_workbook: {
              file: tdk_xlsx_upload(initial_rows)
            }
          }
        end
      end
    end

    assert_redirected_to admin_bas_job_path(job)
    assert_equal "Bank statement upload queued. Processing will continue in the background.", flash[:notice]

    workbook = job.tdk_workbooks.recent.first
    assert_equal "queued", workbook.status
    assert_equal 1, workbook.version_number
    assert workbook.source_file.attached?
    assert_nil job.tdk_workbooks.active_processed.first

    get admin_bas_job_path(job)

    assert_response :success
    assert_select ".tdk-background-status-card .tdk-status-pill.is-working", "Queued"
    assert_select ".tdk-background-status-card .tdk-status-spinner:not(.is-empty)"
    assert_select ".tdk-background-status-card .tdk-status-working-text", "Processing bank statement..."
    assert_select ".tdk-workflow-grid[data-controller~='tdk-workbook-status'] .tdk-export-action-slot[data-tdk-workbook-status-target='downloadAction']"
    assert_includes response.body, "Prepare/download available after processing succeeds."
    refute_includes response.body, "Prepare latest Excel"
    refute_includes response.body, "Open active table"

    perform_enqueued_jobs(only: BasTdkWorkbookProcessingJob)

    workbook.reload
    assert_equal "processed", workbook.status
    assert_equal [ "Date", "Category", "Amount", "GST", "Description" ], workbook.processed_headers
    assert_equal 2, workbook.rows.count

    get admin_bas_job_path(job)

    assert_response :success
    assert_includes response.body, "Synthetic cafe sale"
    assert_select ".tdk-workbook-review-card"
    assert_select ".tdk-active-export-panel", count: 0
    assert_select "h3", text: "Excel download", count: 0
    assert_select "h2", "Editable bank statement table"
    assert_select "input[name='rows[#{workbook.rows.ordered.first.id}][Category]']"
    assert_select "button", text: "Prepare Excel download", count: 1
    assert_select ".tdk-export-action-slot button", text: "Prepare Excel download", count: 1
    assert_select ".tdk-background-status-card button", text: "Prepare Excel download", count: 0
    refute_includes response.body, "Prepare latest Excel"
    refute_includes response.body, "Open active table"

    row = workbook.rows.ordered.first
    patch update_rows_admin_bas_job_tdk_workbook_path(job, workbook), params: {
      page: 1,
      rows: {
        row.id => {
          "Category" => "Meals",
          "GST" => "10.00",
          "Description" => "Edited synthetic cafe sale",
          "Unexpected" => "ignored"
        }
      }
    }

    assert_redirected_to admin_bas_job_path(job, page: 1)
    assert_equal "Saved 1 visible rows.", flash[:notice]
    row.reload
    workbook.reload
    assert_equal "Meals", row.row_data.fetch("Category")
    assert_equal "10.00", row.row_data.fetch("GST")
    assert_equal "Edited synthetic cafe sale", row.row_data.fetch("Description")
    assert_not row.row_data.key?("Unexpected")
    assert_equal "stale", workbook.export_status

    get admin_bas_job_path(job, page: 1)

    assert_response :success
    assert_includes response.body, "Bank statement changed. Prepare a new Excel download to include the latest edits."
    assert_select "button", text: "Prepare Excel download", count: 1

    assert_enqueued_with(job: BasTdkWorkbookExportJob) do
      post prepare_download_admin_bas_job_tdk_workbook_path(job, workbook)
    end

    assert_redirected_to admin_bas_job_path(job)
    assert_equal "Excel export queued. Preparation will continue in the background.", flash[:notice]
    assert_equal "queued", workbook.reload.export_status

    get admin_bas_job_path(job)

    assert_response :success
    assert_select ".tdk-background-status-card", text: /Preparing Excel download\.\.\./
    assert_select ".tdk-background-status-card .tdk-status-spinner:not(.is-empty)"
    assert_select ".tdk-export-action-slot .tdk-export-disabled[aria-disabled='true']"

    get download_admin_bas_job_tdk_workbook_path(job, workbook)
    assert_redirected_to admin_bas_job_path(job)
    assert_equal "Excel export is not ready yet. Prepare Excel download first.", flash[:alert]

    perform_enqueued_jobs(only: BasTdkWorkbookExportJob)

    workbook.reload
    assert workbook.export_ready?

    get download_admin_bas_job_tdk_workbook_path(job, workbook)

    assert_response :success
    assert_equal TdkWorkbookHelper::XLSX_CONTENT_TYPE, response.media_type
    downloaded_rows = tdk_downloaded_table_rows(response.body)
    assert_equal [ "Date", "Category", "Amount", "GST", "Description" ], downloaded_rows.first.first(5)
    assert_equal "Meals", downloaded_rows.second[1]
    assert_equal "10.0", downloaded_rows.second[3]
    assert_equal "Edited synthetic cafe sale", downloaded_rows.second[4]

    get admin_bas_job_path(job)

    assert_response :success
    assert_select "a[href='#{download_admin_bas_job_tdk_workbook_path(job, workbook)}'][data-turbo='false']", text: "Download Excel", count: 1
    assert_select ".tdk-active-export-panel", count: 0

    assert_enqueued_with(job: BasTdkWorkbookProcessingJob) do
      post admin_bas_job_tdk_workbooks_path(job), params: {
        tdk_workbook: {
          file: tdk_xlsx_upload(reupload_rows, filename: "synthetic-edited-bank.xlsx")
        }
      }
    end

    queued_reupload = job.tdk_workbooks.recent.first
    assert_equal "queued", queued_reupload.status
    assert_equal workbook.id, job.tdk_workbooks.active_processed.first.id

    perform_enqueued_jobs(only: BasTdkWorkbookProcessingJob)

    new_workbook = job.tdk_workbooks.active_processed.first
    assert_equal 2, new_workbook.version_number
    assert_equal "superseded", workbook.reload.status
    assert_equal "processed", new_workbook.status
    assert_equal "Fuel", new_workbook.rows.ordered.first.row_data.fetch("Category")
    assert_equal "GST free", new_workbook.rows.ordered.first.row_data.fetch("GST")
  end

  test "admin can process PDF upload render balance sort edit and export" do
    job = create_job(workflow_type: "tdk_group")

    assert_difference "BasTdkWorkbook.count", 1 do
      assert_enqueued_with(job: BasTdkWorkbookProcessingJob) do
        post admin_bas_job_tdk_workbooks_path(job), params: {
          tdk_workbook: {
            file: tdk_pdf_upload(anz_pdf_text, filename: "anz-business-extra.pdf")
          }
        }
      end
    end

    assert_redirected_to admin_bas_job_path(job)
    queued = job.tdk_workbooks.recent.first
    assert_equal "queued", queued.status
    assert_equal "pdf", queued.metadata.fetch("source_type")

    perform_enqueued_jobs(only: BasTdkWorkbookProcessingJob)

    workbook = job.tdk_workbooks.active_processed.first
    assert_equal queued.id, workbook.id
    assert_equal "processed", workbook.status
    assert_equal "anz-business-extra.pdf", workbook.source_filename
    assert_equal [ "Date", "Category", "Amount", "GST", "Description", "Details", "Balance" ], workbook.processed_headers
    assert_equal 3, workbook.rows.count

    get admin_bas_job_path(job)

    assert_response :success
    first_row = workbook.rows.ordered.first
    assert_select "input[name='rows[#{first_row.id}][Category]']"
    assert_select "input[name='rows[#{first_row.id}][GST]']"
    assert_select "input[name='rows[#{first_row.id}][Balance]'].tdk-workbook-cell-input--amount.tdk-workbook-cell-input--balance"
    assert_includes response.body, "VISA DEBIT PURCHASE CARD XXXX / SAMPLE PARKING / EFFECTIVE DATE 05 MAR 2026"
    html = Nokogiri::HTML(response.body)
    balance_header = html.at_css("th.tdk-workbook-col--balance")
    assert balance_header, "expected Balance header to use the dedicated Balance column class"
    assert_includes balance_header.text.squish, "Balance"
    assert_match(/--tdk-balance-input-width:\s*13ch;/, balance_header["style"].to_s)
    amount_header = html.css("th.tdk-workbook-col--amount").find { |header| header.text.squish.include?("Amount") }
    assert amount_header, "expected Amount header to keep the generic amount column class"
    assert_nil html.css("th.tdk-workbook-col--amount").find { |header| header.text.squish.include?("Balance") }
    balance_cell = html.at_css("td.tdk-workbook-col--balance")
    assert_match(/--tdk-balance-input-width:\s*13ch;/, balance_cell["style"].to_s)
    assert html.at_css("td.tdk-workbook-col--balance input[name='rows[#{first_row.id}][Balance]'].tdk-workbook-cell-input--amount.tdk-workbook-cell-input--balance")
    amount_input = html.at_css("td.tdk-workbook-col--amount input[name='rows[#{first_row.id}][Amount]']")
    assert amount_input
    refute_includes amount_input["class"].to_s.split, "tdk-workbook-cell-input--balance"

    get admin_bas_job_path(job, sort: "Balance", direction: "asc", per_page: 10)
    assert_equal [ 7, 5, 10 ], visible_source_rows(response.body)

    get admin_bas_job_path(job, sort: "Balance", direction: "desc", per_page: 10)
    assert_equal [ 10, 5, 7 ], visible_source_rows(response.body)

    patch update_rows_admin_bas_job_tdk_workbook_path(job, workbook), params: {
      page: 1,
      sort: "Balance",
      direction: "asc",
      rows: {
        first_row.id => {
          "Category" => "Parking",
          "GST" => "0.35"
        }
      }
    }

    assert_redirected_to admin_bas_job_path(job, page: 1, sort: "Balance", direction: "asc")
    assert_equal "Parking", first_row.reload.row_data.fetch("Category")
    assert_equal "0.35", first_row.row_data.fetch("GST")

    assert_enqueued_with(job: BasTdkWorkbookExportJob) do
      post prepare_download_admin_bas_job_tdk_workbook_path(job, workbook)
    end
    perform_enqueued_jobs(only: BasTdkWorkbookExportJob)

    get download_admin_bas_job_tdk_workbook_path(job, workbook)

    assert_response :success
    downloaded_rows = tdk_downloaded_table_rows(response.body)
    assert_equal [ "Date", "Category", "Amount", "GST", "Description", "Details", "Balance" ], downloaded_rows.first.first(7)
    assert_equal "2026-03-06", downloaded_rows.second[0]
    assert_equal "Parking", downloaded_rows.second[1]
    assert_equal "4373.7", downloaded_rows.second[2]
    assert_equal "0.35", downloaded_rows.second[3]
    assert_equal "68371.24", downloaded_rows.second[6]
  end

  test "PDF upload stores cleaned scanned OCR descriptions in workbook row data" do
    job = create_job(workflow_type: "tdk_group")

    assert_enqueued_with(job: BasTdkWorkbookProcessingJob) do
      post admin_bas_job_tdk_workbooks_path(job), params: {
        tdk_workbook: {
          file: tdk_pdf_upload(<<~TEXT, filename: "synthetic-scanned-ocr-bank.pdf")
            Bank Service Online
            Statement period 01/05/2026 to 31/05/2026
            Date Description Withdrawals Deposits Running Balance
            01/05/2026 DEPOSIT SAMPLE LOCATION s $ 25.00 -$ 69,975.00
            02/05/2026 TRANSFER DEPOSIT SAMPLE AT LOCATION VI [ c $ 40.00 -$ 69,935.00
            03/05/2026 DEPOSIT SAMPLE CUSTOMER } $ 50.00 -$ 69,885.00
            04/05/2026 LINE FEE $ 10.00 -$ 69,895.00 https://example.internal/path
          TEXT
        }
      }
    end

    perform_enqueued_jobs(only: BasTdkWorkbookProcessingJob)

    workbook = job.tdk_workbooks.active_processed.first
    assert_equal "processed", workbook.status
    assert_equal [
      "DEPOSIT SAMPLE LOCATION",
      "TRANSFER DEPOSIT SAMPLE AT LOCATION VIC",
      "DEPOSIT SAMPLE CUSTOMER",
      "LINE FEE"
    ], workbook.rows.ordered.map { |row| row.row_data.fetch("Description") }
  end

  test "bad uploads fail friendly without replacing active processed workbook" do
    job = create_job(workflow_type: "tdk_group")
    active = create_processed_workbook(job, version_number: 1, description_prefix: "Active synthetic row")

    assert_no_enqueued_jobs do
      assert_difference "BasTdkWorkbook.count", 1 do
        post admin_bas_job_tdk_workbooks_path(job), params: {
          tdk_workbook: {
            file: tdk_text_upload("not a workbook")
          }
        }
      end
    end

    unsupported = job.tdk_workbooks.recent.first
    assert_redirected_to admin_bas_job_path(job)
    assert_equal "failed", unsupported.status
    assert_includes flash[:alert], BasTdk::BankStatementImporter::SUPPORTED_UPLOAD_ERROR
    assert_equal active.id, job.tdk_workbooks.active_processed.first.id

    assert_enqueued_with(job: BasTdkWorkbookProcessingJob) do
      post admin_bas_job_tdk_workbooks_path(job), params: {
        tdk_workbook: {
          file: tdk_xlsx_upload([
            [ "Synthetic Business Pty Ltd" ],
            [ "No transaction table here" ]
          ], filename: "synthetic-bad-bank.xlsx")
        }
      }
    end

    perform_enqueued_jobs(only: BasTdkWorkbookProcessingJob)

    failed = job.tdk_workbooks.recent.first
    assert_equal "failed", failed.status
    assert_equal 3, failed.version_number
    assert_equal "processed", active.reload.status
    assert_equal active.id, job.tdk_workbooks.active_processed.first.id
    assert_includes failed.processing_errors, BasTdk::WorkbookProcessor::FRIENDLY_HEADER_ERROR

    assert_enqueued_with(job: BasTdkWorkbookProcessingJob) do
      post admin_bas_job_tdk_workbooks_path(job), params: {
        tdk_workbook: {
          file: tdk_pdf_upload("", filename: "scanned-bank-statement.pdf")
        }
      }
    end

    perform_enqueued_jobs(only: BasTdkWorkbookProcessingJob)

    scanned_pdf = job.tdk_workbooks.recent.first
    assert_equal "failed", scanned_pdf.status
    assert_equal "processed", active.reload.status
    assert_equal active.id, job.tdk_workbooks.active_processed.first.id
    assert_includes scanned_pdf.processing_errors, BasTdk::LocalOcr::DISABLED_MESSAGE

    get admin_bas_job_path(job)

    assert_response :success
    assert_includes response.body, "Active synthetic row 1"
    assert_includes response.body, "This upload failed. The previous processed bank statement is still active."
    assert_select ".tdk-workbook-review-card"
  end

  test "status endpoint returns latest operation and active workbook metadata" do
    job = create_job(workflow_type: "tdk_group")
    active = create_processed_workbook(job, version_number: 1)
    failed = job.tdk_workbooks.create!(
      status: "failed",
      source_filename: "bad-upload.xlsx",
      version_number: 2,
      row_errors: [ "Synthetic failure" ],
      processed_at: Time.current,
      processed_by: "tdk-workbook-admin"
    )

    get status_admin_bas_job_tdk_workbook_path(job, failed)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal failed.id, payload.fetch("id")
    assert_equal "failed", payload.fetch("status")
    assert_equal 2, payload.fetch("version_number")
    assert_equal [ "Synthetic failure" ], payload.fetch("processing_errors")
    assert_equal active.id, payload.fetch("active_workbook_id")
    assert_equal active.version_number, payload.fetch("active_workbook_version")
    assert_equal active.source_filename, payload.fetch("active_source_filename")
    assert_equal admin_bas_job_path(job), payload.fetch("active_table_url")
    assert_equal prepare_download_admin_bas_job_tdk_workbook_path(job, active), payload.fetch("prepare_download_url")
  end

  test "ready export is invalidated by saved row edits and prepare button returns" do
    job = create_job(workflow_type: "tdk_group")
    workbook = create_processed_workbook(job, version_number: 1)
    workbook.export_file.attach(
      io: StringIO.new("synthetic ready export"),
      filename: "synthetic-ready.xlsx",
      content_type: TdkWorkbookHelper::XLSX_CONTENT_TYPE
    )
    workbook.update!(
      export_status: "processed",
      export_generated_at: Time.current,
      export_finished_at: Time.current
    )

    get admin_bas_job_path(job)

    assert_response :success
    assert_select "a[href='#{download_admin_bas_job_tdk_workbook_path(job, workbook)}'][data-turbo='false']", text: "Download Excel", count: 1
    assert_select ".tdk-active-export-panel", count: 0

    row = workbook.rows.ordered.first
    patch update_rows_admin_bas_job_tdk_workbook_path(job, workbook), params: {
      page: 2,
      per_page: 50,
      sort: "Amount",
      direction: "desc",
      rows: {
        row.id => {
          "Category" => "Repairs",
          "GST" => "10.00",
          "Description" => "Edited after export"
        }
      }
    }

    assert_redirected_to admin_bas_job_path(job, page: 2, per_page: 50, sort: "Amount", direction: "desc")
    assert_equal "stale", workbook.reload.export_status

    get admin_bas_job_path(job)

    assert_response :success
    assert_includes response.body, "Bank statement changed. Prepare a new Excel download to include the latest edits."
    assert_select ".tdk-active-export-panel", count: 0
    assert_select "button", text: "Prepare Excel download", count: 1
  end

  test "update rows saves and normalizes valid amount-like values" do
    job = create_job(workflow_type: "tdk_group")
    workbook = create_processed_workbook(job, version_number: 1, row_count: 2)
    first_row, second_row = workbook.rows.ordered.to_a

    patch update_rows_admin_bas_job_tdk_workbook_path(job, workbook), params: {
      page: 2,
      per_page: 50,
      sort: "Amount",
      direction: "desc",
      rows: {
        first_row.id => {
          "Amount" => "1,000.00",
          "GST" => "(10.00)",
          "Category" => "Meals"
        },
        second_row.id => {
          "Amount" => "-1000",
          "GST" => "",
          "Description" => "Valid amount edit"
        }
      }
    }

    assert_redirected_to admin_bas_job_path(job, page: 2, per_page: 50, sort: "Amount", direction: "desc")
    assert_equal "Saved 2 visible rows.", flash[:notice]
    assert_equal "1,000.00", first_row.reload.row_data.fetch("Amount")
    assert_equal "(10.00)", first_row.row_data.fetch("GST")
    assert_equal "Meals", first_row.row_data.fetch("Category")
    assert_equal "(1,000.00)", second_row.reload.row_data.fetch("Amount")
    assert_equal "", second_row.row_data.fetch("GST")
    assert_equal "Valid amount edit", second_row.row_data.fetch("Description")
  end

  test "update rows rejects invalid amount without saving any submitted rows" do
    job = create_job(workflow_type: "tdk_group")
    workbook = create_processed_workbook(job, version_number: 1, row_count: 2)
    first_row, second_row = workbook.rows.ordered.to_a

    patch update_rows_admin_bas_job_tdk_workbook_path(job, workbook), params: {
      page: 3,
      per_page: 10,
      sort: "Amount",
      direction: "asc",
      rows: {
        first_row.id => {
          "Amount" => "d1,000.00",
          "Category" => "Should not save"
        },
        second_row.id => {
          "Description" => "Should not save either"
        }
      }
    }

    assert_redirected_to admin_bas_job_path(job, page: 3, per_page: 10, sort: "Amount", direction: "asc")
    assert_equal "Amount contains an invalid number on row 5: d1,000.00", flash[:alert]
    assert_equal "1", first_row.reload.row_data.fetch("Amount")
    assert_equal "", first_row.row_data.fetch("Category")
    assert_equal "Synthetic paged row 2", second_row.reload.row_data.fetch("Description")
  end

  test "update rows rejects invalid GST without saving any submitted rows" do
    job = create_job(workflow_type: "tdk_group")
    workbook = create_processed_workbook(job, version_number: 1, row_count: 2)
    first_row, second_row = workbook.rows.ordered.to_a

    patch update_rows_admin_bas_job_tdk_workbook_path(job, workbook), params: {
      page: 1,
      rows: {
        first_row.id => {
          "GST" => "abc",
          "Category" => "Should not save"
        },
        second_row.id => {
          "Amount" => "1,000.00"
        }
      }
    }

    assert_redirected_to admin_bas_job_path(job, page: 1)
    assert_equal "GST contains an invalid number on row 5: abc", flash[:alert]
    assert_equal "", first_row.reload.row_data.fetch("GST")
    assert_equal "", first_row.row_data.fetch("Category")
    assert_equal "2", second_row.reload.row_data.fetch("Amount")
  end

  test "prepare download is only allowed for active processed workbook" do
    job = create_job(workflow_type: "tdk_group")
    old_workbook = create_processed_workbook(job, version_number: 1)
    active = create_processed_workbook(job, version_number: 2, description_prefix: "Active replacement row")
    old_workbook.update!(status: "superseded", superseded_at: Time.current)

    assert_no_enqueued_jobs do
      post prepare_download_admin_bas_job_tdk_workbook_path(job, old_workbook)
    end

    assert_redirected_to admin_bas_job_path(job)
    assert_equal "Only the active processed TDK bank statement can be prepared for download.", flash[:alert]

    assert_enqueued_with(job: BasTdkWorkbookExportJob) do
      post prepare_download_admin_bas_job_tdk_workbook_path(job, active)
    end

    assert_redirected_to admin_bas_job_path(job)
    assert_equal "queued", active.reload.export_status
  end

  test "editable table has anchored section and top and bottom save buttons in the update form" do
    job = create_job(workflow_type: "tdk_group")
    workbook = create_processed_workbook(job, version_number: 1, row_count: 30)

    get admin_bas_job_path(job, page: 2)

    assert_response :success
    html = Nokogiri::HTML(response.body)
    section = html.at_css("section#tdk-active-table.tdk-workbook-review-card")
    assert section, "expected editable table section with stable anchor"
    assert_includes section["data-controller"].to_s.split, "anchor-scroll"

    form = section.at_css("form[action='#{update_rows_admin_bas_job_tdk_workbook_path(job, workbook)}'][method='post']")
    assert form, "expected anchored table section to contain update rows form"
    assert form.at_css("input[name='_method'][value='patch']")
    assert form.at_css("input[name='page'][value='2']")
    assert form.at_css("input[name='per_page'][value='25']")
    assert form.at_css("input[name='sort'][value='source_row']")
    assert form.at_css("input[name='direction'][value='asc']")
    assert_includes form["data-controller"].to_s.split, "submit-guard"
    assert_includes form["data-controller"].to_s.split, "tdk-save-scroll"
    assert_includes form["data-action"].to_s, "submit->tdk-save-scroll#store"

    save_buttons = section.css("button[type='submit'][data-submit-guard-loading-text='Saving rows']").select do |button|
      button.text.squish == "Save visible rows"
    end
    assert_equal 2, save_buttons.size

    top_button = form.at_css(".tdk-workbook-toolbar__actions button[type='submit']")
    bottom_button = section.at_css(".tdk-workbook-table-footer .tdk-workbook-save-action button[type='submit']")
    assert_equal "Save visible rows", top_button.text.squish
    assert_equal "Save visible rows", bottom_button.text.squish
    assert_equal form, top_button.ancestors("form").first
    assert_equal form["id"], bottom_button["form"]
  end

  test "editable table renders date pickers formatted amounts and sortable header links" do
    job = create_job(workflow_type: "tdk_group")
    workbook = create_processed_workbook(job, version_number: 1, row_count: 1)
    row = workbook.rows.ordered.first
    row.update!(
      row_data: row.row_data.merge(
        "Date" => "16/02/2026",
        "Category" => "70089.570000000007",
        "Amount" => "-9762.950000000007",
        "Description" => "8770.7199999999993"
      )
    )

    get admin_bas_job_path(job)

    assert_response :success
    html = Nokogiri::HTML(response.body)
    assert html.at_css("input[type='date'][name='rows[#{row.id}][Date]'][value='2026-02-16'].tdk-workbook-cell-input--date")
    category_input = html.at_css("input[name='rows[#{row.id}][Category]']")
    assert_equal "70089.57", category_input["value"]
    amount_input = html.at_css("input[name='rows[#{row.id}][Amount]'].tdk-workbook-cell-input--amount")
    assert amount_input, "expected amount input to use amount-specific class"
    assert_equal "(9,762.95)", amount_input["value"]
    assert_equal "decimal", amount_input["inputmode"]
    assert_equal BasTdk::WorkbookValues::AMOUNT_INPUT_PATTERN, amount_input["pattern"]
    assert_equal BasTdk::WorkbookValues::AMOUNT_INPUT_TITLE, amount_input["title"]
    description_input = html.at_css("textarea[name='rows[#{row.id}][Description]']")
    assert_equal "8770.72", description_input.text.strip
    refute_includes html.css("th").map { |header| header.text.squish }, "Source row"
    assert_empty html.css("td.tdk-workbook-source-cell")
    assert html.at_css("td.tdk-workbook-col--date.tdk-workbook-cell--date input[type='date'][name='rows[#{row.id}][Date]']")

    date_link = html.at_css("th.tdk-workbook-col--date a.tdk-workbook-sort-link")
    assert date_link, "expected Date header sort link"
    assert_equal "Sort by Date", date_link["title"]
    assert_equal "Sort by Date", date_link["aria-label"]
    assert_equal "↕", date_link.at_css(".tdk-workbook-sort-indicator").text.squish
    uri = URI.parse(date_link["href"])
    params = Rack::Utils.parse_query(uri.query)
    assert_equal "tdk-active-table", uri.fragment
    assert_equal "Date", params.fetch("sort")
    assert_equal "asc", params.fetch("direction")
    assert_equal "1", params.fetch("page")
    assert_equal "25", params.fetch("per_page")
  end

  test "editable table sorts dates amounts and text with blanks last and invalid params safe" do
    job = create_job(workflow_type: "tdk_group")
    create_sortable_workbook(job)

    get admin_bas_job_path(job, sort: "Date", direction: "asc", per_page: 10)
    assert_equal [ 22, 24, 21, 23 ], visible_source_rows(response.body)

    get admin_bas_job_path(job, sort: "Date", direction: "desc", per_page: 10)
    assert_equal [ 21, 24, 22, 23 ], visible_source_rows(response.body)

    get admin_bas_job_path(job, sort: "Amount", direction: "asc", per_page: 10)
    assert_equal [ 24, 21, 22, 23 ], visible_source_rows(response.body)

    get admin_bas_job_path(job, sort: "Amount", direction: "desc", per_page: 10)
    assert_equal [ 22, 21, 24, 23 ], visible_source_rows(response.body)
    amount_desc_link = Nokogiri::HTML(response.body).at_css("th.tdk-workbook-col--amount a.tdk-workbook-sort-link")
    assert_equal "↓", amount_desc_link.at_css(".tdk-workbook-sort-indicator").text.squish

    get admin_bas_job_path(job, sort: "Category", direction: "asc", per_page: 10)
    assert_equal [ 22, 24, 21, 23 ], visible_source_rows(response.body)

    get admin_bas_job_path(job, sort: "Description", direction: "desc", per_page: 10)
    assert_equal [ 24, 21, 22, 23 ], visible_source_rows(response.body)

    get admin_bas_job_path(job, sort: "GST", direction: "asc", per_page: 10)
    assert_response :success
    assert_equal [ 21, 22, 23, 24 ], visible_source_rows(response.body)

    get admin_bas_job_path(job, sort: "GST", direction: "desc", per_page: 10)
    assert_response :success
    assert_equal [ 21, 22, 23, 24 ], visible_source_rows(response.body)

    get admin_bas_job_path(job, sort: "Not a column", direction: "desc", per_page: 999)
    assert_equal [ 21, 22, 23, 24 ], visible_source_rows(response.body)
    assert_select ".tdk-workbook-toolbar__meta span", text: "25 rows per page", count: 0
  end

  test "editable table toolbar omits duplicated active version and total row chips" do
    job = create_job(workflow_type: "tdk_group")
    workbook = create_processed_workbook(job, version_number: 8, row_count: 311)

    get admin_bas_job_path(job, page: 2)

    assert_response :success
    html = Nokogiri::HTML(response.body)
    section = html.at_css("section#tdk-active-table.tdk-workbook-review-card[data-controller~='anchor-scroll']")
    assert section, "expected editable table section with anchor scroll controller"
    workflow_grid = html.at_css(".tdk-workflow-grid[data-controller~='tdk-workbook-status']")
    assert_equal workbook.id.to_s, workflow_grid["data-tdk-workbook-status-rendered-active-workbook-id-value"]
    assert_equal "8", workflow_grid["data-tdk-workbook-status-rendered-active-workbook-version-value"]

    toolbar = section.at_css(".tdk-workbook-toolbar")
    assert toolbar, "expected editable table toolbar"
    assert_includes toolbar.text.squish, "Editable bank statement table"
    assert_includes toolbar.text.squish, "Rows 26-50 of 311"

    meta = toolbar.at_css(".tdk-workbook-toolbar__meta")
    assert meta, "expected toolbar meta area"
    assert_equal [ "Page 2 of 13" ], meta.css("span").map { |span| span.text.squish }
    refute_includes meta.text.squish, "Active v8"
    refute_includes meta.text.squish, "311 rows"

    assert_nil html.at_css(".tdk-current-workbook-card"), "standalone current active panel should be removed"
    status_panel = html.at_css(".tdk-background-status-card")
    assert status_panel, "expected merged status panel"
    assert_includes status_panel.text.squish, "Latest operation"
    assert_includes status_panel.text.squish, "Latest version v8"
    assert_includes status_panel.text.squish, "Operation rows 311"
    assert_includes status_panel.text.squish, "Source file synthetic-active.xlsx"
    source_file_detail = status_panel.at_css(".tdk-status-detail--wide")
    assert source_file_detail, "expected source file detail to span the full status grid"
    assert_includes source_file_detail["class"].to_s.split, "tdk-status-detail"
    assert_equal "Source file", source_file_detail.at_css("dt").text.squish
    refute_includes status_panel.text.squish, "Current active statement"
    refute_includes status_panel.text.squish, "Active version"
    refute_includes status_panel.text.squish, "Detected sheet"
    refute_includes status_panel.text.squish, "Detected header row"
    refute_includes status_panel.text.squish, "Processed at"
  end

  test "editable table pagination is at bottom with first previous next and last controls" do
    job = create_job(workflow_type: "tdk_group")
    workbook = create_processed_workbook(job, version_number: 1, row_count: 311)

    get admin_bas_job_path(job)

    assert_response :success
    assert_select ".tdk-workbook-toolbar .tdk-workbook-pagination", count: 0
    assert_select ".tdk-workbook-table-footer .tdk-workbook-pagination"
    assert_select ".tdk-workbook-pagination .tdk-page-button.is-disabled[aria-label='First page']"
    assert_select ".tdk-workbook-pagination .tdk-page-button.is-disabled[aria-label='Previous page']"
    html = Nokogiri::HTML(response.body)
    assert_tdk_page_link(html, "Next page", job: job, page: 2)
    assert_tdk_page_link(html, "Last page", job: job, page: 13)
    assert_select "form[action='#{update_rows_admin_bas_job_tdk_workbook_path(job, workbook)}'] input[name='page'][value='1']"
    assert_select ".tdk-workbook-page-form select[name='page']"
    assert_select ".tdk-workbook-page-form select[name='per_page']" do
      assert_select "option[value='10']"
      assert_select "option[value='25'][selected='selected']"
      assert_select "option[value='50']"
      assert_select "option[value='100']"
    end

    get admin_bas_job_path(job, page: 4, per_page: 50, sort: "Amount", direction: "desc")

    assert_response :success
    assert_select ".tdk-page-status", "Page 4 of 7"
    html = Nokogiri::HTML(response.body)
    assert_tdk_page_link(html, "First page", job: job, page: 1, per_page: 50, sort: "Amount", direction: "desc")
    assert_tdk_page_link(html, "Previous page", job: job, page: 3, per_page: 50, sort: "Amount", direction: "desc")
    assert_tdk_page_link(html, "Next page", job: job, page: 5, per_page: 50, sort: "Amount", direction: "desc")
    assert_tdk_page_link(html, "Last page", job: job, page: 7, per_page: 50, sort: "Amount", direction: "desc")
    assert_select "form[action='#{update_rows_admin_bas_job_tdk_workbook_path(job, workbook)}'] input[name='page'][value='4']"
    assert_select "form[action='#{update_rows_admin_bas_job_tdk_workbook_path(job, workbook)}'] input[name='per_page'][value='50']"
    assert_select "form[action='#{update_rows_admin_bas_job_tdk_workbook_path(job, workbook)}'] input[name='sort'][value='Amount']"
    assert_select "form[action='#{update_rows_admin_bas_job_tdk_workbook_path(job, workbook)}'] input[name='direction'][value='desc']"
  end

  test "status polling reloads when the active workbook changes without table anchor" do
    controller_source = Rails.root.join("app/javascript/controllers/tdk_workbook_status_controller.js").read

    assert_includes controller_source, "shouldReloadAfterActiveWorkbookChange"
    assert_includes controller_source, "activeWorkbookChanged(payload)"
    assert_includes controller_source, "payload.active_workbook_id"
    assert_includes controller_source, "payload.active_workbook_version"
    assert_includes controller_source, "payload.active_source_filename"
    assert_includes controller_source, "reloadAfterActiveWorkbookChange(payload)"
    assert_includes controller_source, "window.location.assign(this.urlWithCacheBust(payload.active_table_url || window.location.href))"
    assert_includes controller_source, "new URL(url, window.location.href)"
    assert_includes controller_source, "refreshUrl.hash = \"\""
    assert_includes controller_source, "refreshUrl.searchParams.set(\"_tdk_refresh\""
    assert_includes controller_source, "storeAutoRefreshScroll()"
    assert_includes controller_source, "restoreAutoRefreshScroll()"
    assert_not_includes controller_source, "tdk-active-table"
    assert_includes controller_source, "Bank statement changed. Prepare a new Excel download to include the latest edits."
    assert_includes controller_source, "Processing bank statement..."
  end

  test "anchor scroll controller is registered for turbo hash scrolling" do
    controller_source = Rails.root.join("app/javascript/controllers/anchor_scroll_controller.js").read
    index_source = Rails.root.join("app/javascript/controllers/index.js").read
    importmap_source = Rails.root.join("config/importmap.rb").read

    assert_includes controller_source, "window.location.hash"
    assert_includes controller_source, "document.addEventListener(\"turbo:load\", this.scrollAfterTurboLoad)"
    assert_includes controller_source, "scrollToHashOnce()"
    assert_includes controller_source, "removeCurrentHash(hash)"
    assert_includes controller_source, "window.history.replaceState(window.history.state, \"\", url.toString())"
    assert_includes controller_source, "target.scrollIntoView({ block: \"start\", behavior: \"auto\" })"
    assert_not_includes controller_source, "sessionStorage.setItem"
    assert_not_includes controller_source, "PENDING_HASH_KEY"
    assert_includes index_source, "eagerLoadControllersFrom(\"controllers\", application)"
    assert_includes importmap_source, "pin_all_from \"app/javascript/controllers\", under: \"controllers\""
  end

  test "save scroll controller stores row save position and restores it once" do
    controller_source = Rails.root.join("app/javascript/controllers/tdk_save_scroll_controller.js").read

    assert_includes controller_source, "tdk-workbook-rows-save-scroll-y"
    assert_includes controller_source, "window.sessionStorage.setItem(SAVE_SCROLL_KEY, String(window.scrollY))"
    assert_includes controller_source, "window.sessionStorage.removeItem(SAVE_SCROLL_KEY)"
    assert_includes controller_source, "window.scrollTo({ top, left: 0, behavior: \"auto\" })"
    assert_not_includes controller_source, "window.location.hash"
  end

  test "editable table css is compact and avoids desktop truncation" do
    css = Rails.root.join("app/assets/tailwind/application.css").read

    assert_match(/#tdk-active-table\s*\{[^}]*scroll-margin-top: 1\.5rem;/m, css)
    assert_match(/\.tdk-status-detail\s*\{[^}]*background: #f8fafc;/m, css)
    assert_match(/\.tdk-status-detail--wide\s*\{[^}]*grid-column: 1 \/ -1;/m, css)
    assert_match(/\.tdk-workbook-table\s*\{[^}]*width: 100%;[^}]*table-layout: fixed;[^}]*font-size: 0\.875rem/m, css)
    assert_match(/\.tdk-workbook-table\s*\{[^}]*min-width: 92rem/m, css)
    assert_no_match(/\.tdk-workbook-table\s*\{[^}]*width: max-content/m, css)
    assert_match(/\.tdk-workbook-table-wrap\s*\{[^}]*overflow-x: auto;[^}]*overflow-y: visible/m, css)
    assert_no_match(/\.tdk-workbook-table-wrap\s*\{[^}]*max-height/m, css)
    assert_match(/\.tdk-workbook-table th\s*\{[^}]*padding: 0\.5rem;[^}]*font-size: 0\.75rem/m, css)
    assert_match(/\.tdk-workbook-table td\s*\{[^}]*padding: 0\.35rem 0\.65rem 0\.35rem 0\.45rem/m, css)
    assert_no_match(/\.tdk-workbook-table td:first-child,\s*\.tdk-workbook-table th:first-child\s*\{[^}]*width: 5%/m, css)
    assert_match(/\.tdk-workbook-table \.tdk-workbook-cell-input\s*\{[^}]*padding: 0\.4rem 0\.5rem;[^}]*font-size: 0\.875rem/m, css)
    assert_match(/\.tdk-workbook-table \.tdk-workbook-cell-input:not\(\.tdk-workbook-cell-input--textarea\)\s*\{[^}]*min-height: 2\.25rem/m, css)
    assert_match(/\.tdk-workbook-table \.tdk-workbook-cell-input--textarea\s*\{[^}]*min-height: 2\.75rem/m, css)
    assert_match(/\.tdk-workbook-col--source\s*\{[^}]*width: 5%/m, css)
    assert_match(/\.tdk-workbook-col--date\s*\{[^}]*width: 14%;[^}]*min-width: 9\.75rem/m, css)
    assert_match(/\.tdk-workbook-col--category\s*\{[^}]*width: 14%;[^}]*min-width: 9\.5rem/m, css)
    assert_match(/\.tdk-workbook-col--amount\s*\{[^}]*width: 10\.5%/m, css)
    assert_match(/\.tdk-workbook-col--balance\s*\{[^}]*width: var\(--tdk-balance-input-width, 14ch\);[^}]*min-width: var\(--tdk-balance-input-width, 14ch\)/m, css)
    assert_no_match(/\.tdk-workbook-col--balance\s*\{[^}]*width: 10\.5%/m, css)
    assert_match(/\.tdk-workbook-col--description\s*\{[^}]*width: 29%/m, css)
    assert_match(/\.tdk-workbook-table th\.tdk-workbook-col--amount,\s*\.tdk-workbook-table th\.tdk-workbook-col--balance\s*\{[^}]*text-align: right/m, css)
    assert_match(/\.tdk-workbook-table th\.tdk-workbook-col--date,\s*\.tdk-workbook-table \.tdk-workbook-cell--date\s*\{[^}]*padding-right: 0\.95rem/m, css)
    assert_match(/\.tdk-workbook-table \.tdk-workbook-cell-input--date\s*\{[^}]*min-width: 8\.5rem/m, css)
    assert_match(/\.tdk-workbook-table \.tdk-workbook-cell-input--amount\s*\{[^}]*text-align: right/m, css)
    assert_match(/\.tdk-workbook-col--balance \.tdk-workbook-cell-input,\s*\.tdk-workbook-table \.tdk-workbook-cell-input--balance\s*\{[^}]*min-width: var\(--tdk-balance-input-width, 14ch\)/m, css)
    assert_match(/\.tdk-workbook-sort-link\s*\{[^}]*display: inline-flex/m, css)
    assert_match(/\.tdk-workbook-page-selectors\s*\{[^}]*display: inline-flex/m, css)
    assert_match(/\.tdk-workbook-toolbar__actions\s*\{[^}]*display: flex;[^}]*justify-content: flex-end/m, css)
    assert_match(/\.tdk-workbook-toolbar__actions \.btn-primary\s*\{[^}]*white-space: nowrap/m, css)
  end

  test "tdk workflow header uses unified hero action group" do
    css = Rails.root.join("app/assets/tailwind/application.css").read

    assert_match(/\.tdk-workflow-hero,\s*\.tdk-workflow-header-card\s*\{[^}]*display: flex;[^}]*justify-content: space-between/m, css)
    assert_match(/\.tdk-workflow-hero-actions,\s*\.tdk-workflow-header-actions\s*\{[^}]*display: flex;[^}]*align-items: center/m, css)
    assert_no_match(/\.tdk-active-export-panel\s*\{/, css)

    job = create_job(workflow_type: "tdk_group")

    get admin_bas_job_path(job)

    assert_response :success
    assert_select ".tdk-workflow-hero .tdk-workflow-hero-actions" do
      assert_select "a", "Edit job"
      assert_select "a", "Back to BAS"
    end
  end

  test "standard jobs cannot use TDK workbook routes" do
    job = create_job

    get admin_bas_job_path(job)

    assert_response :success
    assert_select ".bas-workspace-heading"
    assert_select ".tdk-workbook-review-card", count: 0

    assert_no_difference "BasTdkWorkbook.count" do
      post admin_bas_job_tdk_workbooks_path(job), params: {
        tdk_workbook: {
          file: tdk_xlsx_upload(initial_rows)
        }
      }
    end

    assert_redirected_to admin_bas_job_path(job)
    assert_equal "TDK bank statement uploads are only available for TDK Group BAS workflow jobs.", flash[:alert]
  end

  private

  def assert_tdk_page_link(html, label, job:, page:, per_page: 25, sort: "source_row", direction: "asc")
    link = html.at_css(".tdk-workbook-pagination a[aria-label='#{label}']")
    assert link, "expected pagination link #{label.inspect}"

    uri = URI.parse(link["href"])
    params = Rack::Utils.parse_query(uri.query)
    assert_equal admin_bas_job_path(job), uri.path
    assert_equal "tdk-active-table", uri.fragment
    assert_equal page.to_s, params.fetch("page")
    assert_equal per_page.to_s, params.fetch("per_page")
    assert_equal sort, params.fetch("sort")
    assert_equal direction, params.fetch("direction")
  end

  def visible_source_rows(body)
    Nokogiri::HTML(body).css("#tdk-active-table tbody tr").map { |row| row["data-source-row-number"].to_i }
  end

  def login_as_admin
    with_modified_env("ADMIN_USERNAME" => "tdk-workbook-admin", "ADMIN_PASSWORD" => "secret-password") do
      post admin_login_path, params: { username: "tdk-workbook-admin", password: "secret-password" }
      assert_redirected_to admin_root_path
    end
  end

  def create_client
    BasClient.create!(
      legal_name: "Synthetic TDK Workflow Client Pty Ltd",
      default_gst_basis: "cash",
      default_reporting_method: "simpler_bas"
    )
  end

  def create_job(attributes = {})
    BasJob.create!({
      bas_client: create_client,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      gst_basis: "cash",
      reporting_method: "simpler_bas"
    }.merge(attributes))
  end

  def create_processed_workbook(job, version_number:, row_count: 2, description_prefix: "Synthetic paged row")
    workbook = job.tdk_workbooks.create!(
      status: "processed",
      source_filename: "synthetic-active.xlsx",
      sheet_name: "Bank Report",
      header_row_number: 4,
      original_headers: [ "Date", "Amount", "Description" ],
      processed_headers: [ "Date", "Category", "Amount", "GST", "Description" ],
      row_count: row_count,
      version_number: version_number,
      processed_at: Time.current,
      processed_by: "tdk-workbook-admin"
    )

    row_count.times do |index|
      workbook.rows.create!(
        position: index + 1,
        source_row_number: index + 5,
        row_data: {
          "Date" => "2026-01-#{((index % 28) + 1).to_s.rjust(2, "0")}",
          "Category" => "",
          "Amount" => (index + 1).to_s,
          "GST" => "",
          "Description" => "#{description_prefix} #{index + 1}"
        }
      )
    end

    workbook
  end

  def create_sortable_workbook(job)
    workbook = job.tdk_workbooks.create!(
      status: "processed",
      source_filename: "synthetic-sortable.xlsx",
      sheet_name: "Bank Report",
      header_row_number: 4,
      original_headers: [ "Date", "Amount", "Description" ],
      processed_headers: [ "Date", "Category", "Amount", "GST", "Description", "Details" ],
      row_count: 4,
      version_number: 1,
      processed_at: Time.current,
      processed_by: "tdk-workbook-admin"
    )

    [
      [ 21, "2026-03-01", "zeta", "-10.00", "", "bravo", "Gamma detail" ],
      [ 22, "2026-01-15", "Alpha", "100.00", "", "alpha", "Alpha detail" ],
      [ 23, "", "", "", "", "", "" ],
      [ 24, "16/02/2026", "beta", "(8,671.67)", "", "Charlie", "Beta detail" ]
    ].each_with_index do |(source_row, date, category, amount, gst, description, details), index|
      workbook.rows.create!(
        position: index + 1,
        source_row_number: source_row,
        row_data: {
          "Date" => date,
          "Category" => category,
          "Amount" => amount,
          "GST" => gst,
          "Description" => description,
          "Details" => details
        }
      )
    end

    workbook
  end

  def job_params(attributes = {})
    {
      bas_client_id: attributes.fetch(:bas_client_id),
      period_start: "2026-01-01",
      period_end: "2026-03-31",
      quarter_label: "",
      workflow_type: attributes.fetch(:workflow_type, "standard"),
      status: "draft",
      gst_basis: "unknown",
      reporting_method: "unknown",
      payroll_applicable: "0",
      cash_transactions_applicable: "0",
      internal_notes: "Synthetic TDK job"
    }.merge(attributes)
  end

  def initial_rows
    [
      [ "Synthetic Business Pty Ltd" ],
      [ "Statement period", "1 Jan 2026 to 31 Mar 2026" ],
      [],
      [ "Date", "Amount", "Description" ],
      [ Date.new(2026, 1, 5), "123.45", "Synthetic cafe sale" ],
      [ Date.new(2026, 1, 6), "-67.89", "Synthetic supplier payment" ]
    ]
  end

  def reupload_rows
    [
      [ "Synthetic Business Pty Ltd" ],
      [ "Statement period", "1 Jan 2026 to 31 Mar 2026" ],
      [],
      [ "Date", "Category", "Amount", "GST", "Description" ],
      [ Date.new(2026, 1, 7), "Fuel", "55.00", "GST free", "Synthetic fuel payment" ]
    ]
  end

  def anz_pdf_text
    <<~TEXT
      ANZ Business Extra
      06 MARCH 2026 TO 08 APRIL 2026
      Date       Transaction Details                                      Withdrawals ($)    Deposits ($)       Balance ($)
      06 MAR     Deposit-Osko Payment SAMPLE CUSTOMER                                        4,373.70           68,371.24
      09 MAR     VISA DEBIT PURCHASE CARD XXXX / SAMPLE PARKING
                 / EFFECTIVE DATE 05 MAR 2026                         3.47                                      68,367.77
      01 APR     Transfer from savings                                                     1,000.00             69,367.77
      TOTALS AT END OF PERIOD
    TEXT
  end
end
