require "test_helper"
require "rack/test"
require_relative "../support/synthetic_pdf_helper"

class AdminBasWorkflowUiTest < ActionDispatch::IntegrationTest
  include SyntheticPdfHelper

  setup do
    login_as_admin
  end

  test "BAS job page shows guided workflow labels warnings and document next actions" do
    job = create_job(reporting_method: "unknown", gst_basis: "unknown")
    csv_document(job, "Synthetic CSV Bank Statement", "bank_statement")
    pdf_document(job)
    csv_document(job, "Synthetic Receipt", "receipt")

    get admin_bas_job_path(job)

    assert_response :success
    assert_select "h2", "BAS workflow"
    assert_select "h3", "Step 1: Upload files"
    assert_select "h3", "Step 2: Import / convert"
    assert_select "h3", "Step 3: Match records"
    assert_select "h3", "Step 4: Generate client queries"
    assert_select "h3", "Step 5: Review BAS report"
    assert_select "h3", "Step 6: Snapshot / approve / lock"

    assert_includes response.body, "Upload source/supporting file"
    assert_includes response.body, "CSV/XLSX imports"
    assert_includes response.body, "Matching &amp; review"
    assert_includes response.body, "Report &amp; snapshots"
    assert_includes response.body, "PDF bank statement history"

    assert_select ".bas-warning-banner", text: /Reporting method is unknown/
    assert_select "h2", "Uploaded source/supporting files"
    assert_includes response.body, "Stored only - no import needed"
    assert_includes response.body, "Convert PDF to preview"
    assert_includes response.body, "Start CSV/XLSX import"
  end

  private

  def login_as_admin
    with_modified_env("ADMIN_USERNAME" => "bas-workflow-ui-admin", "ADMIN_PASSWORD" => "secret-password") do
      post admin_login_path, params: { username: "bas-workflow-ui-admin", password: "secret-password" }
      assert_redirected_to admin_root_path
    end
  end

  def create_client
    BasClient.create!(
      legal_name: "Synthetic Workflow UI Client Pty Ltd",
      default_gst_basis: "unknown",
      default_reporting_method: "unknown"
    )
  end

  def create_job(attributes = {})
    BasJob.create!({
      bas_client: create_client,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      payroll_applicable: true,
      cash_transactions_applicable: true
    }.merge(attributes))
  end

  def csv_document(job, title, document_type)
    document = job.documents.build(
      title: title,
      document_type: document_type,
      uploaded_by: "bas-workflow-ui-admin"
    )
    document.file.attach(csv_upload)
    document.save!
    document
  end

  def pdf_document(job)
    document = job.documents.build(
      title: "Synthetic PDF Bank Statement",
      document_type: "bank_statement",
      uploaded_by: "bas-workflow-ui-admin"
    )
    attach_synthetic_pdf(document, text: sample_statement_text)
    document.save!
    document
  end

  def csv_upload
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/bas_bank_statement.csv").to_s,
      "text/csv"
    )
  end

  def sample_statement_text
    <<~TEXT
      Date Description Debit Credit Balance
      01/01/2026 Synthetic debit 12.34 987.66
    TEXT
  end
end
