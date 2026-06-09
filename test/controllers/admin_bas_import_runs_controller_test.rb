require "test_helper"
require "rack/test"
require_relative "../support/synthetic_pdf_helper"

class AdminBasImportRunsControllerTest < ActionDispatch::IntegrationTest
  include SyntheticPdfHelper

  setup do
    login_as_admin
  end

  test "non-admin cannot access import pages" do
    job = create_job
    document = create_document(job, "bas_bank_statement.csv", "bank_statement")
    import_run = BasImports::Previewer.new(
      bas_job: job,
      bas_document: document,
      import_type: "bank_statement",
      actor_username: "bas-import-admin"
    ).call

    reset!

    get admin_bas_job_import_runs_path(job)
    assert_redirected_to admin_login_path

    get new_admin_bas_job_import_run_path(job)
    assert_redirected_to admin_login_path

    get admin_bas_job_import_run_path(job, import_run)
    assert_redirected_to admin_login_path
  end

  test "admin can view import runs for a job" do
    job = create_job

    get admin_bas_job_import_runs_path(job)

    assert_response :success
    assert_select "h1", job.bas_client.display_name
  end

  test "import preview and confirmation forms include visible submit guard loading text" do
    job = create_job
    document = create_document(job, "bas_bank_statement.csv", "bank_statement")

    get new_admin_bas_job_import_run_path(job, bas_document_id: document.id)

    assert_response :success
    assert_guarded_form admin_bas_job_import_runs_path(job), "Creating preview"
    assert_select "button[data-submit-guard-loading-text='Creating preview']", text: "Create import preview"

    import_run = preview_import(job, "bas_invoice_summary.csv", "invoice_summary", "invoice_summary")

    get admin_bas_job_import_run_path(job, import_run)

    assert_response :success
    assert_guarded_form confirm_admin_bas_job_import_run_path(job, import_run), "Importing"
    assert_select "button[data-submit-guard-loading-text='Importing']", text: "Confirm import"
  end

  test "admin can create preview import run with audit actor" do
    job = create_job
    document = create_document(job, "bas_bank_statement.csv", "bank_statement")

    assert_difference "BasImportRun.count", 1 do
      assert_difference "BasAuditEvent.count", 1 do
        post admin_bas_job_import_runs_path(job), params: {
          bas_import_run: {
            bas_document_id: document.id,
            import_type: "bank_statement"
          }
        }
      end
    end

    import_run = BasImportRun.last
    assert_redirected_to admin_bas_job_import_run_path(job, import_run)
    assert_equal "previewed", import_run.status
    assert_equal "bas-import-admin", BasAuditEvent.last.actor_username
    assert_equal "bas_import_previewed", BasAuditEvent.last.event_type
  end

  test "new preselects document and infers import type for importable spreadsheets" do
    job = create_job
    cases = [
      [ "bas_bank_statement.csv", "bank_statement", "bank_statement" ],
      [ "bas_invoice_summary.csv", "invoice_summary", "invoice_summary" ],
      [ "bas_cash_transactions.csv", "cash_transaction_list", "cash_transactions" ],
      [ "bas_payroll_summary.csv", "payroll_summary", "payroll_summary" ]
    ]

    cases.each do |filename, document_type, import_type|
      document = create_document(job, filename, document_type)

      get new_admin_bas_job_import_run_path(job, bas_document_id: document.id)

      assert_response :success
      assert_select "select[name='bas_import_run[bas_document_id]'] option[selected][value='#{document.id}']", text: document.title
      assert_select "select[name='bas_import_run[import_type]'] option[selected][value='#{import_type}']"
    end
  end

  test "PDF bank statement is not offered as normal CSV XLSX import" do
    job = create_job
    document = pdf_document(job)

    get new_admin_bas_job_import_run_path(job, bas_document_id: document.id)

    assert_response :success
    assert_includes response.body, "PDF bank statements should be converted from the uploaded document row."
    assert_select "select[name='bas_import_run[bas_document_id]'] option[value='#{document.id}']", count: 0
  end

  test "supporting receipt is not offered as importable spreadsheet option" do
    job = create_job
    document = create_document(job, "bas_bank_statement.csv", "receipt")

    get new_admin_bas_job_import_run_path(job, bas_document_id: document.id)

    assert_response :success
    assert_includes response.body, "Receipts and supporting invoices are stored for review and are not imported as CSV/XLSX files."
    assert_select "select[name='bas_import_run[bas_document_id]'] option[value='#{document.id}']", count: 0
  end

  test "direct create rejects documents outside the CSV XLSX import workflow" do
    job = create_job
    document = create_document(job, "bas_bank_statement.csv", "receipt")

    assert_no_difference "BasImportRun.count" do
      post admin_bas_job_import_runs_path(job), params: {
        bas_import_run: {
          bas_document_id: document.id,
          import_type: "bank_statement"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select ".form-errors", text: /must be an uploaded CSV\/XLSX file/
  end

  test "admin can confirm import" do
    job = create_job
    import_run = preview_import(job, "bas_bank_statement.csv", "bank_statement", "bank_statement")

    assert_difference "BasBankTransaction.count", 2 do
      assert_difference "BasAuditEvent.count", 2 do
        post confirm_admin_bas_job_import_run_path(job, import_run), params: {
          column_mapping: import_run.column_mapping
        }
      end
    end

    assert_redirected_to admin_bas_job_import_run_path(job, import_run)
    assert_equal "imported", import_run.reload.status
    assert_equal "review_ready", job.reload.status
    assert_equal "bas-import-admin", BasAuditEvent.last.actor_username
    assert_equal "bas_import_completed", BasAuditEvent.last.event_type
  end

  test "admin can view import errors" do
    job = create_job
    import_run = preview_import(job, "bas_bank_statement_with_error.csv", "bank_statement", "bank_statement")

    post confirm_admin_bas_job_import_run_path(job, import_run), params: {
      column_mapping: import_run.column_mapping
    }

    get admin_bas_job_import_run_path(job, import_run)

    assert_response :success
    assert_select "h2", "Row errors"
    assert_select "td", /Transaction date is invalid/
  end

  test "admin can revert import run" do
    job = create_job
    import_run = preview_import(job, "bas_bank_statement.csv", "bank_statement", "bank_statement")
    BasImports::Importer.new(import_run: import_run, column_mapping: import_run.column_mapping, actor_username: "bas-import-admin").call

    assert_difference "BasBankTransaction.count", -2 do
      assert_difference "BasAuditEvent.count", 1 do
        post revert_admin_bas_job_import_run_path(job, import_run)
      end
    end

    assert_redirected_to admin_bas_job_import_run_path(job, import_run)
    assert_equal "reverted", import_run.reload.status
    assert_equal "bas_import_reverted", BasAuditEvent.last.event_type
  end

  test "locked job blocks import and revert" do
    locked_job = create_job(status: "locked")
    locked_document = create_document(locked_job, "bas_bank_statement.csv", "bank_statement")

    assert_no_difference "BasImportRun.count" do
      post admin_bas_job_import_runs_path(locked_job), params: {
        bas_import_run: {
          bas_document_id: locked_document.id,
          import_type: "bank_statement"
        }
      }
    end

    assert_redirected_to admin_bas_job_import_runs_path(locked_job)

    job = create_job
    import_run = preview_import(job, "bas_bank_statement.csv", "bank_statement", "bank_statement")
    BasImports::Importer.new(import_run: import_run, column_mapping: import_run.column_mapping, actor_username: "bas-import-admin").call
    job.update!(status: "locked")

    assert_no_difference "BasBankTransaction.count" do
      post revert_admin_bas_job_import_run_path(job, import_run)
    end

    assert_redirected_to admin_bas_job_import_runs_path(job)
    assert_equal "imported", import_run.reload.status
  end

  private

  def login_as_admin
    with_modified_env("ADMIN_USERNAME" => "bas-import-admin", "ADMIN_PASSWORD" => "secret-password") do
      post admin_login_path, params: { username: "bas-import-admin", password: "secret-password" }
      assert_redirected_to admin_root_path
    end
  end

  def create_client
    BasClient.create!(
      legal_name: "Synthetic Import Client Pty Ltd",
      default_gst_basis: "cash",
      default_reporting_method: "simpler_bas"
    )
  end

  def create_job(attributes = {})
    BasJob.create!({
      bas_client: create_client,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31)
    }.merge(attributes))
  end

  def create_document(job, filename, document_type)
    document = job.documents.build(
      title: filename.titleize,
      document_type: document_type,
      uploaded_by: "bas-import-admin"
    )
    document.file.attach(
      Rack::Test::UploadedFile.new(
        Rails.root.join("test/fixtures/files/#{filename}").to_s,
        "text/csv"
      )
    )
    document.save!
    document
  end

  def pdf_document(job)
    document = job.documents.build(
      title: "Synthetic PDF Bank Statement",
      document_type: "bank_statement",
      uploaded_by: "bas-import-admin"
    )
    attach_synthetic_pdf(document, text: sample_statement_text)
    document.save!
    document
  end

  def sample_statement_text
    <<~TEXT
      Date Description Debit Credit Balance
      01/01/2026 Synthetic debit 12.34 987.66
    TEXT
  end

  def preview_import(job, filename, document_type, import_type)
    document = create_document(job, filename, document_type)
    BasImports::Previewer.new(
      bas_job: job,
      bas_document: document,
      import_type: import_type,
      actor_username: "bas-import-admin"
    ).call
  end

  def assert_guarded_form(action, loading_text)
    form = Nokogiri::HTML(response.body).at_css("form[action='#{action}'][data-controller='submit-guard'][data-submit-guard-loading-text-value='#{loading_text}']")

    assert form, "Expected guarded form #{action} with loading text #{loading_text.inspect}"
    assert_includes form["data-action"], "turbo:submit-start->submit-guard#submitStart"
    assert_includes form["data-action"], "turbo:submit-end->submit-guard#submitEnd"
  end
end
