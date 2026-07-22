require "test_helper"
require_relative "../support/tdk_workbook_helper"

class AdminBasTdkCodingRunsControllerTest < ActionDispatch::IntegrationTest
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

  test "processed statement exposes save and continue controls and dynamic coding step" do
    job = create_job
    workbook = create_workbook(job, row_count: 2)

    get admin_bas_job_path(job)

    assert_response :success
    assert_select ".tdk-stepper__step[aria-current='step'] strong", "Bank statement review"
    assert_select ".tdk-stepper__step.is-available a[href='#{admin_bas_job_path(job, tdk_step: "coding")}']", text: /Category & GST coding/
    assert_select "button[name='commit_action'][value='continue_to_coding'][form]", text: "Next: Category & GST", count: 2
    assert_select "button.btn-secondary", text: "Save visible rows", count: 2

    get admin_bas_job_path(job, tdk_step: "coding")

    assert_response :success
    assert_select ".tdk-stepper__step[aria-current='step'] strong", "Category & GST coding"
    assert_select "h2", "Step 2 — Category & GST coding review"
    assert_select "a[href='#{admin_bas_job_path(job, tdk_step: "statement")}']", text: "Back to bank statement"
    assert_select ".tdk-coding-reference-card--prominent", count: 1
    assert_select "form[action='#{admin_bas_job_tdk_coding_runs_path(job)}'] input[type='file'][name='tdk_coding_run[reference_file]']"
    assert_select ".tdk-coding-reference-note", text: /current statement stays unchanged/
    assert_includes response.body, workbook.source_filename
  end

  test "newer pending statement disables coding until processing or mapping finishes" do
    job = create_job
    create_workbook(job, version_number: 1)
    job.tdk_workbooks.create!(status: "needs_mapping", version_number: 2, source_filename: "newer.csv")

    get admin_bas_job_path(job)

    assert_response :success
    assert_select ".tdk-stepper__step.is-disabled", text: /Category & GST coding/
    assert_select ".tdk-workbook-continue-disabled[aria-disabled='true']", text: "Next: Category & GST", count: 2

    get admin_bas_job_path(job, tdk_step: "coding")
    assert_select "h2", "Step 1 — Bank statement review"
    assert_select "h2", text: "Step 2 — Category & GST coding review", count: 0
  end

  test "save and continue persists visible edits and rejects an inactive workbook" do
    job = create_job
    active = create_workbook(job, version_number: 2)
    row = active.rows.first

    patch update_rows_admin_bas_job_tdk_workbook_path(job, active), params: {
      commit_action: "continue_to_coding",
      rows: { row.id => { "Description" => "Edited before coding" } }
    }

    assert_redirected_to admin_bas_job_path(job, tdk_step: "coding")
    assert_equal "Edited before coding", row.reload.row_data.fetch("Description")
    assert_equal "Saved 1 visible rows. Continue with Category & GST coding.", flash[:notice]

    inactive = create_workbook(job, version_number: 1)
    old_row = inactive.rows.first
    patch update_rows_admin_bas_job_tdk_workbook_path(job, inactive), params: {
      commit_action: "continue_to_coding",
      rows: { old_row.id => { "Description" => "Must not save" } }
    }

    assert_redirected_to admin_bas_job_path(job)
    assert_equal "Only the active processed TDK bank statement can be edited.", flash[:alert]
    refute_equal "Must not save", old_row.reload.row_data.fetch("Description")
  end

  test "unchanged Step 1 submission is a no-op while actual edits supersede stale coding provenance" do
    job = create_job
    workbook = create_workbook(job)
    workbook.update!(export_status: "processed")
    older_run = create_run(job, workbook, version_number: 1)
    run = create_run(job, workbook, version_number: 2)
    row = workbook.rows.first
    row.update!(
      row_data: row.row_data.merge(
        "Date" => "30/06/2026",
        "Amount" => "-100"
      )
    )

    patch update_rows_admin_bas_job_tdk_workbook_path(job, workbook), params: {
      commit_action: "continue_to_coding",
      rows: {
        row.id => {
          "Date" => "2026-06-30",
          "Category" => "",
          "Amount" => "(100.00)",
          "GST" => "",
          "Description" => row.row_data.fetch("Description")
        }
      }
    }

    assert_equal "processed", workbook.reload.export_status
    assert_equal "processed", older_run.reload.status
    assert_equal "processed", run.reload.status
    assert_equal "Saved 0 visible rows. Continue with Category & GST coding.", flash[:notice]
    assert_equal "30/06/2026", row.reload.row_data.fetch("Date")
    assert_equal "-100", row.row_data.fetch("Amount")

    patch update_rows_admin_bas_job_tdk_workbook_path(job, workbook), params: {
      rows: { row.id => { "Description" => "Changed after coding" } }
    }

    assert_equal "Changed after coding", row.reload.row_data.fetch("Description")
    assert_equal "superseded", older_run.reload.status
    assert_equal "superseded", run.reload.status
    assert run.superseded_at.present?
    assert_includes run.processing_errors.join(" "), "Generate Category & GST suggestions again"
    assert_equal "stale", workbook.reload.export_status
    assert_nil workbook.coding_runs.active_processed.first
    assert BasAuditEvent.exists?(auditable: older_run, event_type: "bas_tdk_coding_run_superseded_after_statement_edit")
    assert BasAuditEvent.exists?(auditable: run, event_type: "bas_tdk_coding_run_superseded_after_statement_edit")
  end

  test "Step 1 edits are blocked while coding suggestions are processing" do
    job = create_job
    workbook = create_workbook(job)
    run = job.tdk_coding_runs.create!(
      target_workbook: workbook,
      version_number: 1,
      status: "processing",
      source_filename: "prior-quarter.csv",
      processing_started_at: Time.current
    )
    row = workbook.rows.first

    patch update_rows_admin_bas_job_tdk_workbook_path(job, workbook), params: {
      rows: { row.id => { "Description" => "Must wait" } }
    }

    assert_equal "Wait for Category & GST suggestion processing to finish before editing the bank statement.", flash[:alert]
    refute_equal "Must wait", row.reload.row_data.fetch("Description")
    assert_equal "processing", run.reload.status
  end

  test "admin uploads prior-quarter reference and queues coding run" do
    job = create_job
    workbook = create_workbook(job)

    assert_difference "BasTdkCodingRun.count", 1 do
      assert_enqueued_with(job: BasTdkCodingRunProcessingJob) do
        post admin_bas_job_tdk_coding_runs_path(job), params: {
          tdk_coding_run: {
            reference_file: tdk_csv_upload("Description,Category,Amount,GST\nFuel stop,Fuel,-110,-10\n", filename: "prior-quarter.csv")
          }
        }
      end
    end

    run = job.tdk_coding_runs.recent.first
    assert_redirected_to admin_bas_job_path(job, tdk_step: "coding")
    assert_equal "queued", run.status
    assert_equal workbook.id, run.target_workbook_id
    assert_equal "prior-quarter.csv", run.source_filename
    assert run.reference_file.attached?
    assert_equal "tdk-coding-admin", run.requested_by
    assert BasAuditEvent.exists?(auditable: run, event_type: "bas_tdk_coding_run_queued")
  end

  test "unsupported reference is recorded as failed without queueing processing" do
    job = create_job
    create_workbook(job)

    assert_no_enqueued_jobs only: BasTdkCodingRunProcessingJob do
      post admin_bas_job_tdk_coding_runs_path(job), params: {
        tdk_coding_run: { reference_file: tdk_text_upload("not a workbook", filename: "prior.pdf", content_type: "application/pdf") }
      }
    end

    run = job.tdk_coding_runs.recent.first
    assert_equal "failed", run.status
    assert_includes run.processing_errors, "Previous-quarter reference must be an XLSX or CSV file."
    assert_redirected_to admin_bas_job_path(job, tdk_step: "coding")
  end

  test "oversized reference is rejected before attachment or background processing" do
    job = create_job
    create_workbook(job)
    tempfile = Tempfile.new([ "oversized-prior-quarter", ".csv" ], Rails.root.join("tmp"))
    tempfile.binmode
    tempfile.truncate(Admin::Bas::TdkCodingRunsController::REFERENCE_MAX_FILE_SIZE + 1)
    tempfile.close
    upload = Rack::Test::UploadedFile.new(tempfile.path, "text/csv", true, original_filename: "oversized.csv")

    assert_no_enqueued_jobs only: BasTdkCodingRunProcessingJob do
      post admin_bas_job_tdk_coding_runs_path(job), params: {
        tdk_coding_run: { reference_file: upload }
      }
    end

    run = job.tdk_coding_runs.recent.first
    assert_equal "failed", run.status
    assert_includes run.processing_errors, "Previous-quarter reference is too large. The maximum file size is 25 MB."
    refute run.reference_file.attached?
    assert_equal Admin::Bas::TdkCodingRunsController::REFERENCE_MAX_FILE_SIZE + 1, run.metadata.fetch("byte_size")
    assert_redirected_to admin_bas_job_path(job, tdk_step: "coding")
  ensure
    tempfile&.unlink
  end

  test "needs-mapping reference renders tolerant one-based columns and valid confirmation resumes processing" do
    job = create_job
    workbook = create_workbook(job)
    run = create_mapping_run(job, workbook)

    get admin_bas_job_path(job, tdk_step: "coding")

    assert_response :success
    assert_select "section#tdk-coding-mapping"
    assert_select "select[name='coding_mapping[columns][1]'] option[selected]", "Description"
    assert_select "select[name='coding_mapping[columns][2]'] option[selected]", "Category"
    assert_select "select[name='coding_mapping[columns][3]'] option[selected]", "Amount"
    assert_select "select[name='coding_mapping[columns][4]'] option[selected]", "GST"
    assert_select "strong", text: "Column A — Narrative"
    assert_select "select[name='coding_mapping[columns][7]']"
    assert_select "strong", text: "Column G"
    assert_includes response.body, "Fuel stop"
    assert_includes response.body, "Fuel from blank header"

    assert_enqueued_with(job: BasTdkCodingRunProcessingJob) do
      patch confirm_mapping_admin_bas_job_tdk_coding_run_path(job, run), params: {
        coding_mapping: {
          header_row_number: 1,
          data_start_row: 2,
          columns: { "1" => "description", "2" => "ignore", "3" => "amount", "4" => "gst", "7" => "category" }
        }
      }
    end

    run.reload
    assert_redirected_to admin_bas_job_path(job, tdk_step: "coding")
    assert_equal "queued", run.status
    assert_equal({ "description" => 1, "amount" => 3, "gst" => 4, "category" => 7 }, run.column_mapping)
    assert_equal run.column_mapping, run.metadata.dig("column_mapping_override").slice("description", "category", "amount", "gst")
    assert_equal 1, run.metadata.dig("column_mapping_override", "header_row_number")
    assert_equal 2, run.metadata.dig("column_mapping_override", "data_start_row")

    perform_enqueued_jobs(only: BasTdkCodingRunProcessingJob)
    assert_equal "processed", run.reload.status
    assert_equal 1, run.reference_row_count
    assert_equal workbook.row_count, run.row_codings.count
  end

  test "mapping screen lets the user correct undetected header and data rows" do
    job = create_job
    workbook = create_workbook(job)
    run = create_mapping_run(job, workbook)
    run.update_columns(
      header_row_number: nil,
      data_start_row: nil,
      metadata: run.metadata.deep_merge(
        "column_detection" => {
          "header_row_number" => nil,
          "data_start_row" => nil
        }
      )
    )

    get admin_bas_job_path(job, tdk_step: "coding")

    assert_response :success
    assert_select "input[type='number'][name='coding_mapping[header_row_number]'][value='1'][min='1'][required]"
    assert_select "input[type='number'][name='coding_mapping[data_start_row]'][value='2'][min='1'][required]"
    assert_select "label[for='coding_mapping_header_row_number']", "Header row"
    assert_select "label[for='coding_mapping_data_start_row']", "First data row"

    assert_enqueued_with(job: BasTdkCodingRunProcessingJob) do
      patch confirm_mapping_admin_bas_job_tdk_coding_run_path(job, run), params: {
        coding_mapping: {
          header_row_number: 3,
          data_start_row: 4,
          columns: { "1" => "description", "2" => "category", "3" => "amount", "4" => "gst" }
        }
      }
    end

    run.reload
    assert_equal 3, run.header_row_number
    assert_equal 4, run.data_start_row
    assert_equal 3, run.metadata.dig("column_mapping_override", "header_row_number")
    assert_equal 4, run.metadata.dig("column_mapping_override", "data_start_row")
  end

  test "mapping validation requires description category and one valid amount shape" do
    job = create_job
    run = create_mapping_run(job, create_workbook(job))

    assert_no_enqueued_jobs only: BasTdkCodingRunProcessingJob do
      patch confirm_mapping_admin_bas_job_tdk_coding_run_path(job, run), params: {
        coding_mapping: {
          header_row_number: 1,
          data_start_row: 2,
          columns: { "1" => "description", "2" => "category", "3" => "amount", "4" => "debit" }
        }
      }
    end

    assert_equal "needs_mapping", run.reload.status
    assert_equal "Amount cannot be combined with Debit or Credit columns.", flash[:alert]

    assert_enqueued_with(job: BasTdkCodingRunProcessingJob) do
      patch confirm_mapping_admin_bas_job_tdk_coding_run_path(job, run), params: {
        coding_mapping: {
          header_row_number: 1,
          data_start_row: 2,
          columns: { "1" => "description", "2" => "category", "3" => "debit", "4" => "credit" }
        }
      }
    end
    assert_equal({ "description" => 1, "category" => 2, "debit" => 3, "credit" => 4 }, run.reload.column_mapping)
  end

  test "coding review renders field provenance warning text counts and filters before pagination" do
    job = create_job
    workbook = create_workbook(job, row_count: 3)
    run, history, rule, manual = create_processed_coding_run(job, workbook)

    get admin_bas_job_path(job, tdk_step: "coding")

    assert_response :success
    assert_select ".tdk-coding-summary .is-warning strong", "1"
    assert_select ".tdk-coding-summary", text: /Rows needing review\s*1/
    assert_select ".tdk-coding-summary", text: /Category review\s*1/
    assert_select ".tdk-coding-summary", text: /GST review\s*1/
    assert_select ".tdk-coding-filter.is-active", text: /All/
    assert_select ".tdk-coding-filter", text: /Category review\s*1/
    assert_select ".tdk-coding-filter", text: /GST review\s*1/
    assert_select ".tdk-coding-filter", text: /Category unclassified\s*0/
    assert_select ".tdk-coding-filter", text: /GST unresolved\s*0/
    assert_select ".tdk-coding-filter span", text: "Unclassified", count: 0
    assert_select ".tdk-coding-source-badge.is-history", text: /Prior-quarter exact match/
    assert_select ".tdk-coding-source-badge.is-rule", text: /Rule suggestion/
    assert_select ".tdk-coding-source-badge.is-manual", text: /Manual/
    assert_select ".tdk-coding-reference-evidence", count: 0
    assert_select ".tdk-coding-provenance p", text: "Matched reference file row 9"
    assert_select "input.tdk-coding-field--warning[name='codings[#{rule.id}][category]']"
    assert_select ".tdk-coding-field-warning", text: "Category needs review"
    assert_includes response.body, "92% confidence"
    assert_select "button[type='submit'][form='coding_review_form_bas_tdk_coding_run_#{run.id}']", text: "Save reviewed rows", count: 2
    assert_select "input[type='checkbox'][name='codings[#{history.id}][reviewed]'][checked]", count: 0
    assert_select "input[type='checkbox'][name='codings[#{rule.id}][reviewed]'][checked]", count: 0
    assert_select "input[type='checkbox'][name='codings[#{manual.id}][reviewed]'][checked]", count: 1
    assert_select "#tdk-coding-review[data-controller~='tdk-resizable-table']"
    assert_select "#tdk-coding-review[data-tdk-resizable-table-storage-key-value^='tdk-coding-column-widths:#{run.id}:']"
    assert_select "[data-tdk-resizable-table-target='topScroll'][data-action*='scrollTableFromTop']", count: 1
    assert_select "[data-tdk-resizable-table-target='tableWrap'][data-action*='scrollTopFromTable']", count: 1
    assert_select "table[data-tdk-resizable-table-target='table']", count: 1
    assert_select "col[data-tdk-resizable-table-target='column']", count: 7
    assert_select "[data-tdk-resizable-table-target='handle'][role='separator']", count: 7
    assert_select "thead a.tdk-workbook-sort-link", count: 7
    assert_select "button[data-action='click->tdk-resizable-table#resetWidths']", count: 1
    assert_select ".tdk-workbook-pagination-group", count: 2
    assert_select "#tdk_coding_page_select_top, #tdk_coding_page_select_bottom", count: 2
    assert_select "#tdk_coding_per_page_select_top, #tdk_coding_per_page_select_bottom", count: 2

    get admin_bas_job_path(job, tdk_step: "coding", coding_filter: "needs_review", coding_per_page: 10)
    assert_equal [ rule.workbook_row.source_row_number ], coding_source_rows(response.body)

    get admin_bas_job_path(job, tdk_step: "coding", coding_filter: "category_review", coding_per_page: 10)
    assert_equal [ rule.workbook_row.source_row_number ], coding_source_rows(response.body)

    get admin_bas_job_path(job, tdk_step: "coding", coding_filter: "gst_review", coding_per_page: 10)
    assert_equal [ rule.workbook_row.source_row_number ], coding_source_rows(response.body)

    get admin_bas_job_path(job, tdk_step: "coding", coding_filter: "prior_match", coding_per_page: 10)
    assert_equal [ history.workbook_row.source_row_number ], coding_source_rows(response.body)

    get admin_bas_job_path(job, tdk_step: "coding", coding_filter: "manual", coding_per_page: 10)
    assert_equal [ manual.workbook_row.source_row_number ], coding_source_rows(response.body)
  end

  test "coding review separates field review and unresolved filters while legacy unclassified remains available" do
    job = create_job
    workbook = create_workbook(job, row_count: 4)
    run = create_run(job, workbook, row_count: 4, suggestion_count: 4, warning_count: 3)
    rows = workbook.rows.ordered.to_a
    category_only = create_coding(
      run,
      rows[0],
      suggested_category: nil,
      suggested_gst_amount: BigDecimal("9.09"),
      category_source: "unmatched",
      gst_source: "previous_quarter_exact",
      category_review_required: true,
      gst_review_required: false
    )
    gst_only = create_coding(
      run,
      rows[1],
      suggested_category: "Fuel",
      suggested_gst_amount: nil,
      category_source: "previous_quarter_exact",
      gst_source: "unmatched",
      category_review_required: false,
      gst_review_required: true
    )
    both = create_coding(
      run,
      rows[2],
      suggested_category: "Motor vehicle expenses",
      suggested_gst_amount: BigDecimal("9.27"),
      category_source: "rule",
      gst_source: "rule",
      category_review_required: true,
      gst_review_required: true
    )
    create_coding(
      run,
      rows[3],
      suggested_category: "Sales",
      suggested_gst_amount: BigDecimal("9.36"),
      category_source: "previous_quarter_exact",
      gst_source: "previous_quarter_exact",
      category_review_required: false,
      gst_review_required: false,
      review_status: "proposed"
    )

    get admin_bas_job_path(job, tdk_step: "coding")

    assert_response :success
    assert_select ".tdk-coding-summary", text: /Rows needing review\s*3/
    assert_select ".tdk-coding-summary", text: /Category review\s*2/
    assert_select ".tdk-coding-summary", text: /GST review\s*2/
    assert_select ".tdk-coding-filter", text: /Category unclassified\s*1/
    assert_select ".tdk-coding-filter", text: /GST unresolved\s*1/

    get admin_bas_job_path(job, tdk_step: "coding", coding_filter: "category_review")
    assert_equal [ category_only, both ].map { |coding| coding.workbook_row.source_row_number }, coding_source_rows(response.body)

    get admin_bas_job_path(job, tdk_step: "coding", coding_filter: "gst_review")
    assert_equal [ gst_only, both ].map { |coding| coding.workbook_row.source_row_number }, coding_source_rows(response.body)

    get admin_bas_job_path(job, tdk_step: "coding", coding_filter: "category_unclassified")
    assert_equal [ category_only.workbook_row.source_row_number ], coding_source_rows(response.body)

    get admin_bas_job_path(job, tdk_step: "coding", coding_filter: "gst_unresolved")
    assert_equal [ gst_only.workbook_row.source_row_number ], coding_source_rows(response.body)

    get admin_bas_job_path(job, tdk_step: "coding", coding_filter: "unclassified")
    assert_equal [ category_only, gst_only ].map { |coding| coding.workbook_row.source_row_number }, coding_source_rows(response.body)
    assert_select ".tdk-coding-filter span", text: "Unclassified", count: 0
  end

  test "coding review sorts typed values before pagination and keeps blanks last" do
    job = create_job
    workbook = create_workbook(job, row_count: 12)
    run = create_run(job, workbook, row_count: 12, suggestion_count: 12, warning_count: 12)

    workbook.rows.ordered.each_with_index do |row, index|
      row.update!(row_data: row.row_data.merge("Amount" => (12 - index).to_s))
      create_coding(run, row, suggested_category: "Category #{index + 1}")
    end

    get admin_bas_job_path(
      job,
      tdk_step: "coding",
      coding_sort: "amount",
      coding_direction: "asc",
      coding_per_page: 10,
      coding_page: 1
    )

    assert_response :success
    assert_equal (4..13).to_a.reverse, coding_source_rows(response.body)
    assert_select "thead a[aria-label='Sort by Amount'][href*='coding_direction=desc']", count: 1
    assert_select ".tdk-workbook-pagination-group", count: 2

    get admin_bas_job_path(
      job,
      tdk_step: "coding",
      coding_sort: "amount",
      coding_direction: "asc",
      coding_per_page: 10,
      coding_page: 2
    )

    assert_equal [ 3, 2 ], coding_source_rows(response.body)

    blank_row = workbook.rows.ordered.last
    blank_row.update!(row_data: blank_row.row_data.merge("Amount" => ""))
    get admin_bas_job_path(job, tdk_step: "coding", coding_sort: "amount", coding_direction: "desc", coding_per_page: 25)

    assert_equal blank_row.source_row_number, coding_source_rows(response.body).last
  end

  test "coding review presents inherited blank GST as neutral prior-quarter evidence" do
    job = create_job
    workbook = create_workbook(job, row_count: 1)
    run = create_run(job, workbook, warning_count: 1)
    coding = create_coding(
      run,
      workbook.rows.first,
      suggested_category: "Sales",
      suggested_gst_amount: nil,
      gst_treatment: "unknown",
      category_source: "previous_quarter_fuzzy",
      gst_source: "previous_quarter_fuzzy",
      category_confidence: 94,
      gst_confidence: 94,
      category_review_required: true,
      gst_review_required: false,
      review_status: "needs_review",
      warning_codes: [ "historical_template_match", "historical_gst_blank_inherited" ],
      reference_source_row_number: 232,
      reference_snapshot: { "description" => "POS 22248700 02 FEB" },
      metadata: { "match_type" => "template", "reference_occurrences" => 73 }
    )

    get admin_bas_job_path(job, tdk_step: "coding")

    assert_response :success
    assert_select "input[name='codings[#{coding.id}][gst]'][value='']", count: 1
    assert_select ".tdk-coding-source-badge.is-neutral", text: /GST: Prior-quarter blank/
    assert_select ".tdk-coding-field-warning", text: "GST needs review", count: 0
    assert_select ".tdk-coding-reference-evidence", text: "Representative reference file row 232 (73 template examples)"
    assert_select ".tdk-coding-reference-example", text: /POS 22248700 02 FEB/
    assert_select ".tdk-coding-information-codes", text: "Prior-quarter GST was blank"
    assert_select ".tdk-coding-warning-codes", text: /Historical gst blank inherited/, count: 0
  end

  test "coding review presents conservative blank GST and historical overrides as neutral information" do
    job = create_job
    workbook = create_workbook(job, row_count: 1)
    run = create_run(job, workbook, warning_count: 1)
    create_coding(
      run,
      workbook.rows.first,
      suggested_category: "Freight",
      suggested_gst_amount: nil,
      category_source: "rule",
      gst_source: "previous_quarter_fuzzy",
      category_review_required: true,
      gst_review_required: false,
      warning_codes: [
        "historical_gst_conservative_blank",
        "historical_category_overridden",
        "category_conflict"
      ]
    )

    get admin_bas_job_path(job, tdk_step: "coding")

    assert_response :success
    assert_select ".tdk-coding-source-badge.is-neutral", text: /GST: Prior-quarter conservative blank/
    assert_select ".tdk-coding-information-codes", text: /Mixed prior-quarter GST — left blank conservatively/
    assert_select ".tdk-coding-information-codes", text: /Historical category overridden/
    assert_select ".tdk-coding-warning-codes", text: "Category conflict"
    assert_select ".tdk-coding-warning-codes", text: /Historical gst conservative blank/, count: 0
    assert_select ".tdk-coding-warning-codes", text: /Historical category overridden/, count: 0
  end

  test "unflagged proposals stay unreviewed until the admin checks Reviewed" do
    job = create_job
    workbook = create_workbook(job, row_count: 1)
    run = create_run(job, workbook)
    coding = create_coding(
      run,
      workbook.rows.first,
      suggested_category: "Fuel",
      suggested_gst_amount: BigDecimal("9.09"),
      category_source: "previous_quarter_exact",
      gst_source: "previous_quarter_exact",
      category_review_required: false,
      gst_review_required: false,
      review_status: "proposed"
    )

    patch update_rows_admin_bas_job_tdk_coding_run_path(job, run), params: {
      codings: { coding.id => { reviewed: "0" } }
    }

    assert_equal "proposed", coding.reload.review_status
    assert_not coding.reviewed?
    assert_nil coding.reviewed_by
    assert_nil coding.reviewed_at
    assert_equal 0, run.reload.reviewed_count
    assert_equal "Saved 0 coding review rows.", flash[:notice]

    patch update_rows_admin_bas_job_tdk_coding_run_path(job, run), params: {
      codings: { coding.id => { reviewed: "1" } }
    }

    assert_equal "accepted", coding.reload.review_status
    assert coding.reviewed?
    assert_equal "tdk-coding-admin", coding.reviewed_by
    assert coding.reviewed_at.present?
    assert_equal 1, run.reload.reviewed_count
    assert_equal "Saved 1 coding review rows.", flash[:notice]
  end

  test "reviewer can accept intentionally blank Category and GST values" do
    job = create_job
    workbook = create_workbook(job)
    run = create_run(job, workbook, warning_count: 1, suggestion_count: 0)
    coding = create_coding(run, workbook.rows.first)

    patch update_rows_admin_bas_job_tdk_coding_run_path(job, run), params: {
      codings: { coding.id => { category: "", gst: "", reviewed: "1" } }
    }

    coding.reload
    assert_equal "accepted", coding.review_status
    assert_nil coding.suggested_category
    assert_nil coding.suggested_gst_amount
    assert_equal "unknown", coding.gst_treatment
    refute coding.category_review_required
    refute coding.gst_review_required
    assert coding.reviewed?
    assert_equal 0, run.reload.warning_count
    assert_equal 1, run.reviewed_count
  end

  test "manual coding edits update workbook provenance GST treatment and review counts atomically" do
    job = create_job
    workbook = create_workbook(job, row_count: 1)
    run = create_run(job, workbook, warning_count: 1)
    coding = create_coding(run, workbook.rows.first, category_source: "rule", gst_source: "rule", category_review_required: true, gst_review_required: true)

    patch update_rows_admin_bas_job_tdk_coding_run_path(job, run), params: {
      coding_filter: "needs_review",
      coding_page: 1,
      coding_per_page: 25,
      codings: { coding.id => { category: "Fuel", gst: "10.00", reviewed: "1" } }
    }

    coding.reload
    run.reload
    assert_redirected_to admin_bas_job_path(job, tdk_step: "coding", coding_filter: "needs_review", coding_page: 1, coding_per_page: 25, anchor: "tdk-coding-review")
    assert_equal "Fuel", coding.suggested_category
    assert_equal BigDecimal("10"), coding.suggested_gst_amount
    assert_equal "manual", coding.category_source
    assert_equal "manual", coding.gst_source
    assert_equal "taxable", coding.gst_treatment
    assert_equal "edited", coding.review_status
    assert_not coding.review_required?
    assert_equal "tdk-coding-admin", coding.reviewed_by
    assert coding.reviewed_at.present?
    assert_equal "Fuel", coding.workbook_row.reload.row_data.fetch("Category")
    assert_equal "10.00", coding.workbook_row.row_data.fetch("GST")
    assert_equal 0, run.warning_count
    assert_equal 1, run.reviewed_count
    assert_equal "stale", workbook.reload.export_status

    patch update_rows_admin_bas_job_tdk_coding_run_path(job, run), params: {
      codings: { coding.id => { category: "Fuel", gst: "10.00", reviewed: "0" } }
    }
    coding.reload
    assert_equal "needs_review", coding.review_status
    assert coding.category_review_required
    assert coding.gst_review_required
    assert_nil coding.reviewed_by
    assert_nil coding.reviewed_at
    assert_equal 1, run.reload.warning_count
    assert_equal 0, run.reviewed_count

    patch update_rows_admin_bas_job_tdk_coding_run_path(job, run), params: {
      codings: { coding.id => { category: "Fuel", gst: "0", reviewed: "1" } }
    }
    assert_equal "no_gst", coding.reload.gst_treatment
    assert_equal BigDecimal("0"), coding.suggested_gst_amount
  end

  test "invalid GST rejects every submitted coding update" do
    job = create_job
    workbook = create_workbook(job, row_count: 2)
    run = create_run(job, workbook, row_count: 2, warning_count: 2)
    first = create_coding(run, workbook.rows.ordered.first)
    second = create_coding(run, workbook.rows.ordered.second)

    patch update_rows_admin_bas_job_tdk_coding_run_path(job, run), params: {
      codings: {
        first.id => { category: "Must not save", gst: "abc", reviewed: "1" },
        second.id => { category: "Also unchanged", gst: "0", reviewed: "1" }
      }
    }

    assert_equal "GST contains an invalid number on row #{first.workbook_row.source_row_number}: abc", flash[:alert]
    assert_nil first.reload.suggested_category
    assert_nil second.reload.suggested_category
    assert_equal "processed", run.reload.status
  end

  test "status endpoint reports terminal and active review information" do
    job = create_job
    workbook = create_workbook(job)
    run = create_run(job, workbook, warning_count: 1)

    get status_admin_bas_job_tdk_coding_run_path(job, run)

    assert_response :success
    payload = response.parsed_body
    assert_equal "processed", payload.fetch("status")
    assert_equal true, payload.fetch("terminal")
    assert_equal run.id, payload.fetch("active_run_id")
    assert_equal 1, payload.fetch("warning_count")
    assert_equal admin_bas_job_path(job, tdk_step: "coding"), payload.fetch("workflow_url")
  end

  private

  def login_as_admin
    with_modified_env("ADMIN_USERNAME" => "tdk-coding-admin", "ADMIN_PASSWORD" => "secret-password") do
      post admin_login_path, params: { username: "tdk-coding-admin", password: "secret-password" }
      assert_redirected_to admin_root_path
    end
  end

  def create_job
    client = BasClient.create!(
      legal_name: "Synthetic Coding Client Pty Ltd",
      default_gst_basis: "cash",
      default_reporting_method: "simpler_bas"
    )
    BasJob.create!(
      bas_client: client,
      workflow_type: "tdk_group",
      period_start: Date.new(2026, 4, 1),
      period_end: Date.new(2026, 6, 30),
      gst_basis: "cash",
      reporting_method: "simpler_bas"
    )
  end

  def create_workbook(job, version_number: 1, row_count: 1)
    workbook = job.tdk_workbooks.create!(
      status: "processed",
      version_number: version_number,
      source_filename: "current-quarter-v#{version_number}.csv",
      processed_headers: [ "Date", "Category", "Amount", "GST", "Description" ],
      row_count: row_count,
      processed_at: Time.current,
      processed_by: "tdk-coding-admin"
    )
    row_count.times do |index|
      workbook.rows.create!(
        position: index + 1,
        source_row_number: index + 2,
        row_data: {
          "Date" => "2026-04-#{(index + 1).to_s.rjust(2, "0")}",
          "Category" => "",
          "Amount" => (100 + index).to_s,
          "GST" => "",
          "Description" => "Synthetic transaction #{index + 1}"
        }
      )
    end
    workbook
  end

  def create_mapping_run(job, workbook)
    run = job.tdk_coding_runs.create!(
      target_workbook: workbook,
      version_number: 1,
      status: "needs_mapping",
      source_filename: "prior-mapping.csv",
      header_row_number: 1,
      data_start_row: 2,
      row_errors: [ "Select the reference columns." ],
      metadata: {
        "column_detection" => {
          "header_row_number" => 1,
          "data_start_row" => 2,
          "columns" => [
            { "source_column" => 1, "header" => "Narrative", "candidate_roles" => [ "description" ], "sample_values" => [ "Fuel stop" ] },
            { "source_column" => 2, "header" => "Account", "candidate_roles" => [ "category" ], "sample_values" => [ "Fuel" ] },
            { "source_column" => 3, "header" => "Value", "candidate_roles" => [ "amount" ], "sample_values" => [ "-110.00" ] },
            { "source_column" => 4, "header" => "Tax", "candidate_roles" => [ "gst" ], "sample_values" => [ "-10.00" ] },
            { "source_column" => 7, "header" => "", "candidate_roles" => [], "sample_values" => [ "Fuel from blank header" ] }
          ]
        }
      }
    )
    run.reference_file.attach(tdk_csv_upload("Narrative,Account,Value,Tax,,,\nFuel stop,Legacy,-110,-10,,,Fuel from blank header\n", filename: "prior-mapping.csv"))
    run
  end

  def create_processed_coding_run(job, workbook)
    run = create_run(job, workbook, row_count: 3, suggestion_count: 3, warning_count: 1, reviewed_count: 1)
    rows = workbook.rows.ordered.to_a
    history = create_coding(
      run,
      rows[0],
      suggested_category: "Fuel",
      suggested_gst_amount: BigDecimal("9.09"),
      category_source: "previous_quarter_exact",
      gst_source: "previous_quarter_exact",
      category_confidence: 100,
      gst_confidence: 100,
      category_review_required: false,
      gst_review_required: false,
      review_status: "proposed",
      reference_source_row_number: 9
    )
    rule = create_coding(
      run,
      rows[1],
      suggested_category: "Motor vehicle expenses",
      suggested_gst_amount: BigDecimal("9.18"),
      category_source: "rule",
      gst_source: "rule",
      category_confidence: 92,
      gst_confidence: 75,
      category_review_required: true,
      gst_review_required: true,
      review_status: "needs_review",
      warning_codes: [ "rule_based_category" ],
      explanation: "Fuel keyword rule; accountant review required."
    )
    manual = create_coding(
      run,
      rows[2],
      suggested_category: "Repairs",
      suggested_gst_amount: BigDecimal("0"),
      category_source: "manual",
      gst_source: "manual",
      category_confidence: 100,
      gst_confidence: 100,
      category_review_required: false,
      gst_review_required: false,
      review_status: "edited",
      reviewed_by: "tdk-coding-admin",
      reviewed_at: Time.current
    )
    [ run, history, rule, manual ]
  end

  def create_run(job, workbook, attributes = {})
    job.tdk_coding_runs.create!({
      target_workbook: workbook,
      version_number: 1,
      status: "processed",
      source_filename: "prior-quarter.csv",
      reference_row_count: 10,
      row_count: workbook.row_count,
      suggestion_count: workbook.row_count,
      warning_count: attributes.fetch(:warning_count, 0),
      reviewed_count: attributes.fetch(:reviewed_count, 0),
      processed_at: Time.current,
      processing_finished_at: Time.current,
      ruleset_version: "au-bas-v1"
    }.merge(attributes.except(:warning_count, :reviewed_count)))
  end

  def create_coding(run, row, attributes = {})
    gst_amount = attributes[:suggested_gst_amount]
    default_gst_treatment = if gst_amount.nil?
      "unknown"
    elsif gst_amount.to_d.zero?
      "no_gst"
    else
      "taxable"
    end

    run.row_codings.create!({
      workbook_row: row,
      category_source: "unmatched",
      gst_source: "unmatched",
      gst_treatment: default_gst_treatment,
      category_review_required: true,
      gst_review_required: true,
      review_status: "needs_review"
    }.merge(attributes))
  end

  def coding_source_rows(body)
    Nokogiri::HTML(body).css("#tdk-coding-review tbody tr").map { |row| row["data-source-row-number"].to_i }
  end
end
