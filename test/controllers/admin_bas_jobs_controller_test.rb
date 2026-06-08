require "test_helper"
require "rack/test"

class AdminBasJobsControllerTest < ActionDispatch::IntegrationTest
  setup do
    login_as_admin
  end

  test "draft unlocked job can be deleted with working paper records" do
    job = create_job
    records = create_working_papers(job)
    client = job.bas_client

    assert_difference "BasJob.count", -1 do
      delete admin_bas_job_path(job)
    end

    assert_redirected_to admin_bas_client_path(client)
    assert_equal "BAS job was deleted.", flash[:notice]

    assert_working_papers_deleted(records)
  end

  test "uploaded BAS document attachment association is removed when job is deleted" do
    job = create_job
    document = create_csv_document(job)
    attachment_id = document.file.attachment.id

    delete admin_bas_job_path(job)

    assert_not ActiveStorage::Attachment.exists?(attachment_id)
  end

  test "locked job cannot be deleted" do
    job = create_job(status: "locked")

    assert_no_difference "BasJob.count" do
      delete admin_bas_job_path(job)
    end

    assert_redirected_to admin_bas_job_path(job)
    assert_equal BasJob::CLEANUP_DELETE_BLOCKED_MESSAGE, flash[:alert]
  end

  test "job with final approved snapshot cannot be deleted" do
    job = create_job
    BasReportSnapshot.create!(
      bas_job: job,
      status: "final",
      totals: { "gst_payable" => "0.0" },
      generated_at: Time.current,
      approved_at: Time.current,
      approved_by: "bas-jobs-admin"
    )

    assert_no_difference "BasJob.count" do
      delete admin_bas_job_path(job)
    end

    assert_redirected_to admin_bas_job_path(job)
    assert_equal BasJob::CLEANUP_DELETE_BLOCKED_MESSAGE, flash[:alert]
  end

  test "draft job page shows delete draft test job action" do
    job = create_job

    get admin_bas_job_path(job)

    assert_response :success
    assert_select "h2", "Danger zone"
    assert_select "button", "Delete draft/test job"
  end

  test "locked job page shows deletion blocked explanation" do
    job = create_job(status: "locked")

    get admin_bas_job_path(job)

    assert_response :success
    assert_select "button", text: "Delete draft/test job", count: 0
    assert_includes response.body, "Locked/final BAS jobs cannot be deleted."
  end

  test "new job form client dropdown uses BasClient display_name" do
    client = create_client(
      legal_name: "Synthetic Legal Client Pty Ltd",
      trading_name: "Synthetic Legal Trading",
      abn: "12345678901",
      notes: "leave blank or Acme Test"
    )

    get new_admin_bas_job_path

    assert_response :success
    assert_select "select[name='bas_job[bas_client_id]'] option[value='#{client.id}']", text: client.display_name.squish
    assert_includes client.display_name, "Synthetic Legal Client Pty Ltd"
    assert_not_includes response.body, ">Synthetic Legal Trading</option>"
    assert_not_includes response.body, client.notes
  end

  test "new job form client dropdown uses legal name as primary label" do
    client = create_client(
      legal_name: "Synthetic Primary Legal Pty Ltd",
      trading_name: "Primary"
    )

    get new_admin_bas_job_path

    assert_response :success
    assert_select "select[name='bas_job[bas_client_id]'] option[value='#{client.id}']", text: "Synthetic Primary Legal Pty Ltd (Primary)"
  end

  test "client name on job show links to client show" do
    client = create_client(legal_name: "Synthetic Linked Client Pty Ltd")
    job = create_job(bas_client: client)

    get admin_bas_job_path(job)

    assert_response :success
    assert_select "a[href='#{admin_bas_client_path(client)}']", text: client.display_name
    assert_select "a[href='#{admin_bas_client_path(client)}']", text: "View client details"
  end

  private

  def login_as_admin
    with_modified_env("ADMIN_USERNAME" => "bas-jobs-admin", "ADMIN_PASSWORD" => "secret-password") do
      post admin_login_path, params: { username: "bas-jobs-admin", password: "secret-password" }
      assert_redirected_to admin_root_path
    end
  end

  def create_client(attributes = {})
    BasClient.create!({
      legal_name: "Synthetic Jobs Controller Client Pty Ltd"
    }.merge(attributes))
  end

  def create_job(attributes = {})
    client = attributes.delete(:bas_client) || create_client

    BasJob.create!({
      bas_client: client,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      gst_basis: "cash",
      reporting_method: "simpler_bas"
    }.merge(attributes))
  end

  def create_working_papers(job)
    csv_document = create_csv_document(job)
    pdf_document = create_pdf_document(job)
    import_run = BasImportRun.create!(
      bas_job: job,
      bas_document: csv_document,
      import_type: "bank_statement",
      status: "imported"
    )
    bank_transaction = BasBankTransaction.create!(
      bas_job: job,
      bas_import_run: import_run,
      transaction_date: Date.new(2026, 1, 5),
      description: "Synthetic bank item",
      amount: BigDecimal("100.00")
    )
    invoice = BasInvoice.create!(
      bas_job: job,
      bas_import_run: import_run,
      invoice_number: "INV-DELETE-1",
      total_amount: BigDecimal("100.00")
    )
    cash_transaction = BasCashTransaction.create!(
      bas_job: job,
      bas_import_run: import_run,
      transaction_date: Date.new(2026, 1, 6),
      description: "Synthetic cash item",
      total_amount: BigDecimal("55.00")
    )
    payroll_summary = BasPayrollSummary.create!(
      bas_job: job,
      bas_import_run: import_run,
      gross_wages: BigDecimal("1000.00")
    )
    match = BasMatch.create!(
      bas_job: job,
      match_type: "invoice_to_bank_transaction",
      matched_amount: BigDecimal("100.00")
    )
    match_item = BasMatchItem.create!(
      bas_match: match,
      matchable: bank_transaction,
      amount: BigDecimal("100.00")
    )
    query = BasQuery.create!(
      bas_job: job,
      title: "Synthetic cleanup query",
      created_by: "bas-jobs-admin",
      updated_by: "bas-jobs-admin"
    )
    adjustment = BasAdjustment.create!(
      bas_job: job,
      adjustment_type: "gst_on_sales",
      label: "Synthetic adjustment",
      amount: BigDecimal("10.00"),
      reason: "Synthetic cleanup test"
    )
    report_snapshot = BasReportSnapshot.create!(
      bas_job: job,
      status: "draft",
      totals: { "gst_payable" => "0.0" },
      generated_at: Time.current,
      generated_by: "bas-jobs-admin"
    )
    ai_run = BasAiExtractionRun.create!(
      bas_job: job,
      bas_document: csv_document,
      status: "completed",
      input_kind: "document_text",
      provider: "stub"
    )
    ai_suggestion = BasAiSuggestion.create!(
      bas_job: job,
      bas_ai_extraction_run: ai_run,
      suggestion_type: "summary",
      suggested_data: { "summary" => "Synthetic cleanup" }
    )
    conversion_run = BasDocumentConversionRun.create!(
      bas_job: job,
      source_bas_document: pdf_document,
      status: "previewed"
    )
    audit_event = BasAuditEvent.create!(
      bas_job: job,
      auditable: job,
      event_type: "bas_cleanup_test_event",
      actor_username: "bas-jobs-admin"
    )

    {
      documents: [ csv_document.id, pdf_document.id ],
      import_run: import_run.id,
      bank_transaction: bank_transaction.id,
      invoice: invoice.id,
      cash_transaction: cash_transaction.id,
      payroll_summary: payroll_summary.id,
      match: match.id,
      match_item: match_item.id,
      query: query.id,
      adjustment: adjustment.id,
      report_snapshot: report_snapshot.id,
      ai_run: ai_run.id,
      ai_suggestion: ai_suggestion.id,
      conversion_run: conversion_run.id,
      audit_event: audit_event.id
    }
  end

  def assert_working_papers_deleted(records)
    records.fetch(:documents).each do |document_id|
      assert_not BasDocument.exists?(document_id)
      assert_not ActiveStorage::Attachment.exists?(record_type: "BasDocument", record_id: document_id)
    end
    assert_not BasImportRun.exists?(records.fetch(:import_run))
    assert_not BasBankTransaction.exists?(records.fetch(:bank_transaction))
    assert_not BasInvoice.exists?(records.fetch(:invoice))
    assert_not BasCashTransaction.exists?(records.fetch(:cash_transaction))
    assert_not BasPayrollSummary.exists?(records.fetch(:payroll_summary))
    assert_not BasMatch.exists?(records.fetch(:match))
    assert_not BasMatchItem.exists?(records.fetch(:match_item))
    assert_not BasQuery.exists?(records.fetch(:query))
    assert_not BasAdjustment.exists?(records.fetch(:adjustment))
    assert_not BasReportSnapshot.exists?(records.fetch(:report_snapshot))
    assert_not BasAiExtractionRun.exists?(records.fetch(:ai_run))
    assert_not BasAiSuggestion.exists?(records.fetch(:ai_suggestion))
    assert_not BasDocumentConversionRun.exists?(records.fetch(:conversion_run))
    assert_not BasAuditEvent.exists?(records.fetch(:audit_event))
  end

  def create_csv_document(job)
    document = job.documents.build(
      title: "Synthetic cleanup CSV",
      document_type: "bank_statement",
      uploaded_by: "bas-jobs-admin"
    )
    document.file.attach(csv_upload)
    document.save!
    document
  end

  def create_pdf_document(job)
    document = job.documents.build(
      title: "Synthetic cleanup PDF",
      document_type: "bank_statement",
      uploaded_by: "bas-jobs-admin"
    )
    document.file.attach(
      io: StringIO.new("%PDF-1.4\nSynthetic BAS cleanup PDF\n"),
      filename: "synthetic-cleanup.pdf",
      content_type: "application/pdf"
    )
    document.save!
    document
  end

  def csv_upload
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/bas_bank_statement.csv").to_s,
      "text/csv"
    )
  end
end
