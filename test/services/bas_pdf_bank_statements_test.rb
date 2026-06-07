require "test_helper"
require_relative "../support/synthetic_pdf_helper"

class BasPdfBankStatementsTest < ActiveSupport::TestCase
  include SyntheticPdfHelper

  test "text extractor reads synthetic text based PDF" do
    document = pdf_document(sample_statement_text)

    result = BasPdfBankStatements::TextExtractor.new(bas_document: document).call

    assert_equal 1, result.page_count
    assert_includes result.text, "Commonwealth Bank"
    assert_includes result.text, "01/01/2026"
  end

  test "text extractor fails safely when PDF has no readable text" do
    document = pdf_document("")

    error = assert_raises(BasPdfBankStatements::TextExtractor::ExtractionError) do
      BasPdfBankStatements::TextExtractor.new(bas_document: document).call
    end

    assert_equal BasPdfBankStatements::TextExtractor::UNREADABLE_MESSAGE, error.message
  end

  test "transaction parser extracts rows and detects bank name" do
    result = BasPdfBankStatements::TransactionParser.new(text: sample_statement_text).call

    assert_equal "Commonwealth Bank", result.detected_bank_name
    assert_equal 3, result.rows.size
    assert_equal "2026-01-01", result.rows.first.fetch("transaction_date")
    assert_equal "Synthetic debit", result.rows.first.fetch("description")
  end

  test "transaction parser handles debit credit amount and balance" do
    result = BasPdfBankStatements::TransactionParser.new(text: sample_statement_text).call
    debit_row, credit_row, amount_row = result.rows

    assert_equal "12.34", debit_row.fetch("debit")
    assert_nil debit_row.fetch("credit")
    assert_equal "-12.34", debit_row.fetch("amount")
    assert_equal "987.66", debit_row.fetch("balance")

    assert_nil credit_row.fetch("debit")
    assert_equal "50.00", credit_row.fetch("credit")
    assert_equal "50.00", credit_row.fetch("amount")
    assert_equal "1037.66", credit_row.fetch("balance")

    assert_nil amount_row.fetch("debit")
    assert_nil amount_row.fetch("credit")
    assert_equal "22.00", amount_row.fetch("amount")
  end

  test "confidence scorer flags low confidence rows" do
    parsed = BasPdfBankStatements::TransactionParser.new(text: "01/01/2026 Missing amount only").call
    result = BasPdfBankStatements::ConfidenceScorer.new(rows: parsed.rows).call

    assert_equal 1, result.row_errors.size
    assert_match "Amount is missing or unclear", result.row_errors.first.fetch("message")
    assert result.rows.first.fetch("confidence") < 70
  end

  test "csv builder creates expected headers and rows" do
    csv = BasPdfBankStatements::CsvBuilder.new(rows: [
      {
        "transaction_date" => "2026-01-01",
        "description" => "Synthetic debit",
        "debit" => "12.34",
        "amount" => "-12.34",
        "balance" => "987.66"
      }
    ]).call
    parsed = CSV.parse(csv, headers: true)

    assert_equal BasPdfBankStatements::CsvBuilder::HEADERS, parsed.headers
    assert_equal "2026-01-01", parsed.first.fetch("Date")
    assert_equal "Synthetic debit", parsed.first.fetch("Description")
  end

  test "csv builder escapes formula like values" do
    csv = BasPdfBankStatements::CsvBuilder.new(rows: [
      {
        "transaction_date" => "2026-01-01",
        "description" => "=HYPERLINK(\"http://example.test\")",
        "amount" => "10.00"
      }
    ]).call
    parsed = CSV.parse(csv, headers: true)

    assert_equal "'=HYPERLINK(\"http://example.test\")", parsed.first.fetch("Description")
  end

  test "conversion runner creates preview rows and safe audit events" do
    job = bas_job
    document = pdf_document(sample_statement_text_with_secret, job: job)

    assert_difference "BasDocumentConversionRun.count", 1 do
      assert_difference "BasAuditEvent.count", 2 do
        @conversion_run = BasPdfBankStatements::ConversionRunner.new(
          bas_job: job,
          source_bas_document: document,
          actor_username: "pdf-service"
        ).call
      end
    end

    assert_equal "previewed", @conversion_run.status
    assert_equal 3, @conversion_run.row_count
    assert_equal 0, @conversion_run.error_count
    assert_equal "bas_pdf_bank_statement_conversion_previewed", BasAuditEvent.last.event_type
    metadata_text = BasAuditEvent.where(bas_job: job).map(&:metadata).to_json
    assert_no_match "TOP SECRET PDF TEXT", metadata_text
  end

  test "conversion runner records row errors without importing records" do
    job = bas_job
    document = pdf_document("01/01/2026 Missing amount only", job: job)

    assert_no_difference "BasBankTransaction.count" do
      @conversion_run = BasPdfBankStatements::ConversionRunner.new(
        bas_job: job,
        source_bas_document: document,
        actor_username: "pdf-service"
      ).call
    end

    assert_equal "previewed", @conversion_run.status
    assert_equal 1, @conversion_run.error_count
    assert_match "Amount is missing or unclear", @conversion_run.row_errors.first.fetch("message")
  end

  test "import runner creates import run and bank transactions" do
    conversion_run = preview_conversion(sample_statement_text)

    assert_difference "BasImportRun.count", 1 do
      assert_difference "BasBankTransaction.count", 3 do
        @result = BasPdfBankStatements::ImportRunner.new(
          conversion_run: conversion_run,
          actor_username: "pdf-service"
        ).call
      end
    end

    assert_equal "imported", conversion_run.reload.status
    assert_equal "bank_statement", @result.import_run.import_type
    assert_equal 3, @result.imported_count
    assert_equal BigDecimal("-12.34"), conversion_run.bas_job.bank_transactions.order(:source_row_number).first.amount
  end

  test "import and match runner imports then runs matching" do
    job = bas_job
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
    conversion_run = preview_conversion(matching_statement_text, job: job)

    assert_difference "BasBankTransaction.count", 1 do
      assert_difference "BasMatch.count", 1 do
        @result = BasPdfBankStatements::ImportAndMatchRunner.new(
          conversion_run: conversion_run,
          actor_username: "pdf-service"
        ).call
      end
    end

    assert_equal "matched", conversion_run.reload.status
    assert_equal 1, @result.imported_count
    assert_equal 1, @result.proposed_match_count
    assert_equal "bas_pdf_bank_statement_imported_and_matched", BasAuditEvent.last.event_type
  end

  test "conversion and import audit metadata excludes raw PDF text" do
    conversion_run = preview_conversion(sample_statement_text_with_secret)

    BasPdfBankStatements::ImportRunner.new(
      conversion_run: conversion_run,
      actor_username: "pdf-service"
    ).call

    metadata_text = BasAuditEvent.where(bas_job: conversion_run.bas_job).map(&:metadata).to_json
    assert_no_match "TOP SECRET PDF TEXT", metadata_text
  end

  private

  def preview_conversion(text, job: bas_job)
    document = pdf_document(text, job: job)
    BasPdfBankStatements::ConversionRunner.new(
      bas_job: job,
      source_bas_document: document,
      actor_username: "pdf-service"
    ).call
  end

  def bas_job
    client = BasClient.create!(legal_name: "Synthetic PDF Client Pty Ltd")
    BasJob.create!(
      bas_client: client,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31)
    )
  end

  def pdf_document(text, job: bas_job)
    document = job.documents.build(
      title: "Synthetic PDF Bank Statement",
      document_type: "bank_statement",
      uploaded_by: "pdf-service"
    )
    attach_synthetic_pdf(document, text: text)
    document.save!
    document
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

  def sample_statement_text_with_secret
    <<~TEXT
      Commonwealth Bank
      Date Description Debit Credit Balance
      01/01/2026 TOP SECRET PDF TEXT debit 12.34 987.66
      02/01/2026 Synthetic credit CR 50.00 1037.66
      2026-01-03 Card refund 22.00 1059.66
    TEXT
  end
end
