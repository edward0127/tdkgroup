require "test_helper"
require_relative "../support/synthetic_pdf_helper"

class BasDocumentConversionRunTest < ActiveSupport::TestCase
  include SyntheticPdfHelper

  test "validates required associations and allowlisted values" do
    job = bas_job
    document = pdf_document(job)
    conversion_run = BasDocumentConversionRun.new(
      bas_job: job,
      source_bas_document: document,
      conversion_type: "bank_statement_pdf",
      status: "previewed"
    )

    assert conversion_run.valid?

    conversion_run.conversion_type = "invoice_pdf"
    assert_not conversion_run.valid?
    assert_includes conversion_run.errors[:conversion_type], "is not included in the list"

    conversion_run.conversion_type = "bank_statement_pdf"
    conversion_run.status = "complete"
    assert_not conversion_run.valid?
    assert_includes conversion_run.errors[:status], "is not included in the list"
  end

  test "source document must belong to same job" do
    job = bas_job
    other_job = bas_job(legal_name: "Other Synthetic Client Pty Ltd")
    conversion_run = BasDocumentConversionRun.new(
      bas_job: job,
      source_bas_document: pdf_document(other_job),
      conversion_type: "bank_statement_pdf",
      status: "pending"
    )

    assert_not conversion_run.valid?
    assert_includes conversion_run.errors[:source_bas_document], "must belong to the same BAS job"
  end

  test "source document must be a PDF" do
    job = bas_job
    conversion_run = BasDocumentConversionRun.new(
      bas_job: job,
      source_bas_document: csv_document(job),
      conversion_type: "bank_statement_pdf",
      status: "pending"
    )

    assert_not conversion_run.valid?
    assert_includes conversion_run.errors[:source_bas_document], "must be a PDF"
  end

  test "source document must be a bank statement" do
    job = bas_job
    conversion_run = BasDocumentConversionRun.new(
      bas_job: job,
      source_bas_document: pdf_document(job, document_type: "sales_invoice"),
      conversion_type: "bank_statement_pdf",
      status: "pending"
    )

    assert_not conversion_run.valid?
    assert_includes conversion_run.errors[:source_bas_document], "must be a bank statement"
  end

  test "bas import run must belong to same job" do
    job = bas_job
    other_job = bas_job(legal_name: "Other Import Client Pty Ltd")
    other_import_run = BasImportRun.create!(
      bas_job: other_job,
      bas_document: pdf_document(other_job),
      import_type: "bank_statement",
      status: "pending"
    )

    conversion_run = BasDocumentConversionRun.new(
      bas_job: job,
      source_bas_document: pdf_document(job),
      bas_import_run: other_import_run,
      conversion_type: "bank_statement_pdf",
      status: "previewed"
    )

    assert_not conversion_run.valid?
    assert_includes conversion_run.errors[:bas_import_run], "must belong to the same BAS job"
  end

  private

  def bas_job(legal_name: "Synthetic Conversion Client Pty Ltd")
    client = BasClient.create!(legal_name: legal_name)
    BasJob.create!(
      bas_client: client,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31)
    )
  end

  def pdf_document(job, document_type: "bank_statement")
    document = job.documents.build(
      title: "Synthetic Bank Statement",
      document_type: document_type,
      uploaded_by: "model-test"
    )
    attach_synthetic_pdf(document, text: "01/01/2026 Synthetic debit 12.34 987.66")
    document.save!
    document
  end

  def csv_document(job)
    document = job.documents.build(
      title: "Synthetic Bank Statement CSV",
      document_type: "bank_statement",
      uploaded_by: "model-test"
    )
    document.file.attach(
      io: StringIO.new("Date,Description,Amount\n01/01/2026,Synthetic,1.00\n"),
      filename: "synthetic_bank_statement.csv",
      content_type: "text/csv"
    )
    document.save!
    document
  end
end
