require "test_helper"
require_relative "../support/synthetic_pdf_helper"

class AdminBasDocumentConversionRunsControllerTest < ActionDispatch::IntegrationTest
  include SyntheticPdfHelper

  setup do
    login_as_admin
  end

  test "non-admin cannot access conversion pages or actions" do
    job = create_job
    document = pdf_document(job)
    conversion_run = preview_conversion(job, document)

    reset!

    get admin_bas_job_document_conversion_runs_path(job)
    assert_redirected_to admin_login_path

    get admin_bas_job_document_conversion_run_path(job, conversion_run)
    assert_redirected_to admin_login_path

    post admin_bas_job_document_conversion_runs_path(job), params: { bas_document_id: document.id }
    assert_redirected_to admin_login_path

    post confirm_import_admin_bas_job_document_conversion_run_path(job, conversion_run)
    assert_redirected_to admin_login_path

    get download_csv_admin_bas_job_document_conversion_run_path(job, conversion_run)
    assert_redirected_to admin_login_path
  end

  test "admin can create conversion run for bank statement PDF" do
    job = create_job
    document = pdf_document(job)

    assert_difference "BasDocumentConversionRun.count", 1 do
      assert_difference "BasAuditEvent.count", 2 do
        post admin_bas_job_document_conversion_runs_path(job), params: { bas_document_id: document.id }
      end
    end

    conversion_run = BasDocumentConversionRun.last
    assert_redirected_to admin_bas_job_document_conversion_run_path(job, conversion_run)
    assert_equal "previewed", conversion_run.status
    assert_equal "bas_pdf_bank_statement_conversion_previewed", BasAuditEvent.last.event_type
  end

  test "admin cannot create conversion run for non bank statement PDF" do
    job = create_job
    document = pdf_document(job, document_type: "sales_invoice")

    assert_no_difference "BasDocumentConversionRun.count" do
      post admin_bas_job_document_conversion_runs_path(job), params: { bas_document_id: document.id }
    end

    assert_redirected_to admin_bas_job_path(job)
  end

  test "admin can view conversion preview" do
    job = create_job
    conversion_run = preview_conversion(job)

    get admin_bas_job_document_conversion_run_path(job, conversion_run)

    assert_response :success
    assert_select "h1", "Synthetic PDF Bank Statement"
    assert_select "p", /This preview was extracted from a standard bank-downloaded PDF/
    assert_select "button", "Confirm import"
    assert_select "button", text: "Confirm Import and Run Matching", count: 0
    assert_select "td", "Synthetic debit"
  end

  test "admin can confirm import" do
    job = create_job
    conversion_run = preview_conversion(job)

    assert_difference "BasImportRun.count", 1 do
      assert_difference "BasBankTransaction.count", 3 do
        post confirm_import_admin_bas_job_document_conversion_run_path(job, conversion_run)
      end
    end

    assert_redirected_to admin_bas_job_document_conversion_run_path(job, conversion_run)
    assert_equal "imported", conversion_run.reload.status
    assert_equal "bas_pdf_bank_statement_imported", BasAuditEvent.last.event_type
  end

  test "admin can confirm import and run matching" do
    job = create_job
    BasInvoice.create!(
      bas_job: job,
      direction: "sale",
      invoice_number: "INV-001",
      issue_date: Date.new(2026, 1, 1),
      paid_date: Date.new(2026, 1, 1),
      party_name: "Acme Customer",
      total_amount: BigDecimal("110.00"),
      gst_amount: BigDecimal("10.00"),
      net_amount: BigDecimal("100.00"),
      payment_method: "bank",
      gst_code: "taxable"
    )
    conversion_run = preview_conversion(job, nil, matching_statement_text)

    assert_no_difference "BasQuery.count" do
      assert_difference "BasBankTransaction.count", 1 do
        assert_difference "BasMatch.count", 1 do
          post confirm_import_and_match_admin_bas_job_document_conversion_run_path(job, conversion_run)
        end
      end
    end

    assert_redirected_to admin_bas_job_document_conversion_run_path(job, conversion_run)
    assert_equal "matched", conversion_run.reload.status
    assert_equal "bas_pdf_bank_statement_imported_and_matched", BasAuditEvent.last.event_type
  end

  test "conversion preview page does not encourage one click query generation" do
    job = create_job
    conversion_run = preview_conversion(job)

    get admin_bas_job_document_conversion_run_path(job, conversion_run)

    assert_response :success
    assert_select "button", "Confirm import"
    assert_select "button", text: "Confirm Import and Run Matching", count: 0
    assert_no_match "Generate client queries", response.body
  end

  test "confirm import and match direct action does not create client queries" do
    job = create_job
    BasInvoice.create!(
      bas_job: job,
      direction: "sale",
      invoice_number: "INV-001",
      issue_date: Date.new(2026, 1, 1),
      paid_date: Date.new(2026, 1, 1),
      party_name: "Acme Customer",
      total_amount: BigDecimal("110.00"),
      gst_amount: BigDecimal("10.00"),
      net_amount: BigDecimal("100.00"),
      payment_method: "bank",
      gst_code: "taxable"
    )
    conversion_run = preview_conversion(job, nil, matching_statement_text)

    assert_no_difference "BasQuery.count" do
      assert_difference "BasMatch.count", 1 do
        post confirm_import_and_match_admin_bas_job_document_conversion_run_path(job, conversion_run)
      end
    end

    assert_redirected_to admin_bas_job_document_conversion_run_path(job, conversion_run)
    assert_equal "matched", conversion_run.reload.status
    assert_equal "PDF bank statement imported and matching suggestions created. Review proposed matches before generating client queries.", flash[:notice]
  end

  test "admin can download converted CSV" do
    job = create_job
    conversion_run = preview_conversion(job)

    get download_csv_admin_bas_job_document_conversion_run_path(job, conversion_run)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.body, "Date,Description,Details,Reference,Debit,Credit,Amount,Balance,Bank Account Name"
    assert_includes response.body, "Synthetic debit"
  end

  test "locked job blocks conversion import match and abandon actions" do
    locked_job = create_job(status: "locked")
    locked_document = pdf_document(locked_job)

    assert_no_difference "BasDocumentConversionRun.count" do
      post admin_bas_job_document_conversion_runs_path(locked_job), params: { bas_document_id: locked_document.id }
    end
    assert_redirected_to admin_bas_job_document_conversion_runs_path(locked_job)

    job = create_job
    conversion_run = preview_conversion(job)
    job.update!(status: "locked")

    get admin_bas_job_document_conversion_run_path(job, conversion_run)
    assert_response :success

    assert_no_difference "BasBankTransaction.count" do
      post confirm_import_admin_bas_job_document_conversion_run_path(job, conversion_run)
    end
    assert_redirected_to admin_bas_job_document_conversion_runs_path(job)
    assert_equal "previewed", conversion_run.reload.status

    assert_no_difference "BasBankTransaction.count" do
      post confirm_import_and_match_admin_bas_job_document_conversion_run_path(job, conversion_run)
    end
    assert_redirected_to admin_bas_job_document_conversion_runs_path(job)
    assert_equal "previewed", conversion_run.reload.status

    post abandon_admin_bas_job_document_conversion_run_path(job, conversion_run)
    assert_redirected_to admin_bas_job_document_conversion_runs_path(job)
    assert_equal "previewed", conversion_run.reload.status
  end

  test "admin can abandon previewed conversion with audit event" do
    job = create_job
    conversion_run = preview_conversion(job)

    assert_difference "BasAuditEvent.count", 1 do
      post abandon_admin_bas_job_document_conversion_run_path(job, conversion_run)
    end

    assert_redirected_to admin_bas_job_document_conversion_run_path(job, conversion_run)
    assert_equal "abandoned", conversion_run.reload.status
    assert_equal "bas_pdf_bank_statement_conversion_abandoned", BasAuditEvent.last.event_type
  end

  private

  def login_as_admin
    with_modified_env("ADMIN_USERNAME" => "pdf-admin", "ADMIN_PASSWORD" => "secret-password") do
      post admin_login_path, params: { username: "pdf-admin", password: "secret-password" }
      assert_redirected_to admin_root_path
    end
  end

  def create_client
    BasClient.create!(
      legal_name: "Synthetic PDF Admin Client Pty Ltd",
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

  def pdf_document(job, text = sample_statement_text, document_type: "bank_statement")
    document = job.documents.build(
      title: "Synthetic PDF Bank Statement",
      document_type: document_type,
      uploaded_by: "pdf-admin"
    )
    attach_synthetic_pdf(document, text: text)
    document.save!
    document
  end

  def preview_conversion(job, document = nil, text = sample_statement_text)
    document ||= pdf_document(job, text)
    BasPdfBankStatements::ConversionRunner.new(
      bas_job: job,
      source_bas_document: document,
      actor_username: "pdf-admin"
    ).call
  end

  def sample_statement_text
    <<~TEXT
      Commonwealth Bank
      Date Description Debit Credit Balance
      01/01/2026 Synthetic debit 12.34 987.66
      02/01/2026 Synthetic credit CR 50.00 1037.66
      2026-01-03 Card refund 22.00 1059.66
    TEXT
  end

  def matching_statement_text
    <<~TEXT
      Date Description Debit Credit Balance
      01/01/2026 Acme Customer invoice INV-001 CR 110.00 1110.00
    TEXT
  end
end
