require "test_helper"
require_relative "../support/tdk_workbook_helper"

class BasTdkWorkbookProcessorTest < ActiveSupport::TestCase
  include TdkWorkbookHelper

  test "reads custom accounting formatted workbook as raw values" do
    workbook = process_upload(tdk_xlsx_upload([
      [ "Synthetic Business Pty Ltd" ],
      [ "Statement period", "1 Jan 2026 to 31 Mar 2026" ],
      [],
      [ "Date", "Amount", "Description", nil, nil ],
      [ 46022, 123.45, "Synthetic cafe sale", "Card ref 123", "Terminal 9" ],
      [ 46023, -67.89, "Synthetic supplier payment", "Card ref 456", nil ]
    ], accounting_format_columns: [ 2 ]))

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal "Bank Report", workbook.sheet_name
    assert_equal 4, workbook.header_row_number
    assert_equal [ "Date", "Amount", "Description" ], workbook.original_headers.first(3)
    assert_equal [ "Date", "Category", "Amount", "GST", "Description", "Details" ], workbook.processed_headers
    assert_equal 2, workbook.row_count

    rows = workbook.rows.ordered.to_a
    assert_equal "2025-12-31", rows.first.row_data.fetch("Date")
    assert_equal "", rows.first.row_data.fetch("Category")
    assert_equal "", rows.first.row_data.fetch("GST")
    assert_equal "123.45", rows.first.row_data.fetch("Amount")
    assert_equal "Card ref 123 | Terminal 9", rows.first.row_data.fetch("Details")
    assert_equal "-67.89", rows.second.row_data.fetch("Amount")
  end

  test "cleans Excel decimal noise without changing references or normal text" do
    workbook = process_upload(tdk_xlsx_upload([
      [ "Synthetic Business Pty Ltd" ],
      [ "Statement period", "1 Jan 2026 to 31 Mar 2026" ],
      [],
      [ "Date", "Amount", "Description", "Reference", nil, nil, nil ],
      [ 46022, "70089.570000000007", "Synthetic cafe sale", "7341056315", "8770.7199999999993", "123.456789", "ABC123" ]
    ]))

    assert workbook.processed?, workbook.processing_errors.to_sentence
    row = workbook.rows.ordered.first
    assert_equal "70089.57", row.row_data.fetch("Amount")
    assert_equal "7341056315", row.row_data.fetch("Reference")
    assert_equal "8770.72 | 123.456789 | ABC123", row.row_data.fetch("Details")
  end

  test "detects header row after metadata and adds Category and GST columns" do
    workbook = process_upload(tdk_xlsx_upload([
      [ "Synthetic Business Pty Ltd" ],
      [ "Statement period", "1 Jan 2026 to 31 Mar 2026" ],
      [],
      [ "Date", "Amount", "Description" ],
      [ Date.new(2026, 1, 5), 123.45, "Synthetic cafe sale" ],
      [ Date.new(2026, 1, 6), -67.89, "Synthetic supplier payment" ]
    ]))

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal "Bank Report", workbook.sheet_name
    assert_equal 4, workbook.header_row_number
    assert_equal [ "Date", "Amount", "Description" ], workbook.original_headers.first(3)
    assert_equal [ "Date", "Category", "Amount", "GST", "Description" ], workbook.processed_headers
    assert_equal 2, workbook.row_count

    first_row = workbook.rows.ordered.first
    assert_equal 5, first_row.source_row_number
    assert_equal "", first_row.row_data.fetch("Category")
    assert_equal "", first_row.row_data.fetch("GST")
    assert_equal "Synthetic cafe sale", first_row.row_data.fetch("Description")
  end

  test "preserves existing Category and GST values" do
    workbook = process_upload(tdk_xlsx_upload([
      [ "Report export" ],
      [],
      [],
      [ "Transaction Date", "Category", "Transaction Amount", "GST", "Details" ],
      [ 46055, "Meals", 88.00, "GST included", "Synthetic lunch" ]
    ], accounting_format_columns: [ 3 ]))

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal [ "Transaction Date", "Category", "Transaction Amount", "GST", "Details" ], workbook.processed_headers
    row = workbook.rows.ordered.first
    assert_equal "Meals", row.row_data.fetch("Category")
    assert_equal "GST included", row.row_data.fetch("GST")
    assert_equal "Synthetic lunch", row.row_data.fetch("Details")
  end

  test "synthesises Details from extra cells with blank headers" do
    workbook = process_upload(tdk_xlsx_upload([
      [ "Report export" ],
      [],
      [],
      [ "Date", "Amount", "Description", nil, nil ],
      [ Date.new(2026, 3, 1), "42.00", "Synthetic card purchase", "Card ref 123", "Terminal 9" ]
    ]))

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_includes workbook.processed_headers, "Details"

    row = workbook.rows.ordered.first
    assert_equal "Card ref 123 | Terminal 9", row.row_data.fetch("Details")
  end

  test "records friendly error when header cannot be detected" do
    workbook = process_upload(tdk_xlsx_upload([
      [ "Synthetic Business Pty Ltd" ],
      [ "Statement export" ],
      [ "No transaction table here" ]
    ]))

    assert workbook.failed?
    assert_equal 0, workbook.row_count
    assert_includes workbook.processing_errors, BasTdk::WorkbookProcessor::FRIENDLY_HEADER_ERROR
  end

  test "records friendly errors for unsupported and bad bank statement files" do
    unsupported = process_upload(tdk_text_upload("not a workbook"))

    assert unsupported.failed?
    assert_includes unsupported.processing_errors, BasTdk::BankStatementImporter::SUPPORTED_UPLOAD_ERROR

    bad_workbook = process_upload(tdk_text_upload("not a zip", filename: "synthetic-bad.xlsx", content_type: TdkWorkbookHelper::XLSX_CONTENT_TYPE))

    assert bad_workbook.failed?
    assert_includes bad_workbook.processing_errors, "Bank statement Excel could not be read. Please upload a valid XLSX file."
  end

  test "parses text based Westpac style PDF rows" do
    workbook = process_upload(tdk_pdf_upload(westpac_pdf_text, filename: "westpac-business-one.pdf"))

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal "PDF transaction table", workbook.sheet_name
    assert_equal [ "Date", "Category", "Amount", "GST", "Description", "Details", "Balance" ], workbook.processed_headers
    assert_equal 2, workbook.row_count

    credit_row, debit_row = workbook.rows.ordered.to_a
    assert_equal "2025-12-08", credit_row.row_data.fetch("Date")
    assert_equal "", credit_row.row_data.fetch("Category")
    assert_equal "", credit_row.row_data.fetch("GST")
    assert_equal "5049.00", credit_row.row_data.fetch("Amount")
    assert_equal "6696.81", credit_row.row_data.fetch("Balance")
    assert_equal "Deposit-Osko Payment 2234694 Ccon Group Pty Ltd", credit_row.row_data.fetch("Description")

    assert_equal "2025-12-09", debit_row.row_data.fetch("Date")
    assert_equal "-71930.00", debit_row.row_data.fetch("Amount")
    assert_equal "-65233.19", debit_row.row_data.fetch("Balance")
    assert_equal "Office rent transfer", debit_row.row_data.fetch("Description")
  end

  test "parses text based ANZ style PDF rows and infers month name dates" do
    workbook = process_upload(tdk_pdf_upload(anz_pdf_text, filename: "anz-business-extra.pdf"))

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal [ "Date", "Category", "Amount", "GST", "Description", "Details", "Balance" ], workbook.processed_headers
    assert_equal 3, workbook.row_count

    deposit_row, withdrawal_row, april_row = workbook.rows.ordered.to_a
    assert_equal "2026-03-06", deposit_row.row_data.fetch("Date")
    assert_equal "4373.70", deposit_row.row_data.fetch("Amount")
    assert_equal "68371.24", deposit_row.row_data.fetch("Balance")

    assert_equal "2026-03-09", withdrawal_row.row_data.fetch("Date")
    assert_equal "-3.47", withdrawal_row.row_data.fetch("Amount")
    assert_equal "68367.77", withdrawal_row.row_data.fetch("Balance")
    assert_equal "VISA DEBIT PURCHASE CARD 7805 / EASYPARK PRAHRAN / EFFECTIVE DATE 05 MAR 2026", withdrawal_row.row_data.fetch("Description")

    assert_equal "2026-04-01", april_row.row_data.fetch("Date")
    assert_equal "1000.00", april_row.row_data.fetch("Amount")
  end

  test "image based or unreadable PDF fails with selectable text guidance" do
    workbook = process_upload(tdk_pdf_upload("", filename: "scanned-bank-statement.pdf"))

    assert workbook.failed?
    assert_equal 0, workbook.row_count
    assert_includes workbook.processing_errors, BasTdk::PdfStatementParser::UNREADABLE_PDF_MESSAGE
  end

  private

  def process_upload(upload)
    BasTdk::WorkbookProcessor.new(
      bas_job: bas_job,
      uploaded_file: upload,
      actor_username: "tdk-processor-test"
    ).call
  end

  def bas_job
    @bas_job ||= BasJob.create!(
      bas_client: BasClient.create!(legal_name: "Synthetic Processor Client Pty Ltd"),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      workflow_type: "tdk_group"
    )
  end

  def westpac_pdf_text
    <<~TEXT
      Westpac Business One
      Statement period 05 December 2025 to 05 January 2026
      DATE       TRANSACTION DESCRIPTION                                      DEBIT              CREDIT             BALANCE
      STATEMENT OPENING BALANCE                                                                                       1,647.81
      08/12/25   Deposit-Osko Payment 2234694 Ccon Group Pty Ltd                                  5,049.00           6,696.81
      09/12/25   Office rent transfer                                      71,930.00                              (65,233.19)
      TOTALS AT END OF PAGE                                                71,930.00             5,049.00
      CLOSING BALANCE                                                                                              (65,233.19)
    TEXT
  end

  def anz_pdf_text
    <<~TEXT
      ANZ Business Extra
      06 MARCH 2026 TO 08 APRIL 2026
      Date       Transaction Details                                      Withdrawals ($)    Deposits ($)       Balance ($)
      06 MAR     Deposit-Osko Payment Customer                                               4,373.70           68,371.24
      09 MAR     VISA DEBIT PURCHASE CARD 7805 / EASYPARK PRAHRAN
                 / EFFECTIVE DATE 05 MAR 2026                         3.47                                      68,367.77
      01 APR     Transfer from savings                                                     1,000.00             69,367.77
      TOTALS AT END OF PERIOD
    TEXT
  end
end
