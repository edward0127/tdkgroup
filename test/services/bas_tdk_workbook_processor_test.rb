require "test_helper"
require_relative "../support/tdk_workbook_helper"

class BasTdkWorkbookProcessorTest < ActiveSupport::TestCase
  include TdkWorkbookHelper

  LocalOcrDouble = Struct.new(:result) do
    def call
      result
    end
  end

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
    workbook = nil
    ocr_called = false
    with_stubbed_local_ocr_new(->(**_kwargs) {
      ocr_called = true
      LocalOcrDouble.new(nil)
    }) do
      workbook = process_upload(tdk_pdf_upload(westpac_pdf_text, filename: "westpac-business-one.pdf"))
    end

    refute ocr_called, "OCR should not run for readable PDFs"
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
    assert_equal "Deposit-Osko Payment SAMPLE001 SAMPLE CUSTOMER", credit_row.row_data.fetch("Description")

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
    assert_equal "VISA DEBIT PURCHASE CARD XXXX / SAMPLE PARKING / EFFECTIVE DATE 05 MAR 2026", withdrawal_row.row_data.fetch("Description")

    assert_equal "2026-04-01", april_row.row_data.fetch("Date")
    assert_equal "1000.00", april_row.row_data.fetch("Amount")
  end

  test "image based PDF fails with local OCR disabled guidance" do
    with_modified_env("TDK_LOCAL_OCR_ENABLED" => "false") do
      workbook = process_upload(tdk_pdf_upload("", filename: "scanned-bank-statement.pdf"))

      assert workbook.failed?
      assert_equal 0, workbook.row_count
      assert_includes workbook.processing_errors, BasTdk::LocalOcr::DISABLED_MESSAGE
      assert_equal false, workbook.metadata.fetch("ocr_attempted")
      assert_equal "disabled", workbook.metadata.fetch("ocr_status")
    end
  end

  test "image based PDF imports through local OCR sidecar text" do
    ocr_result = BasTdk::LocalOcr::Result.new(
      success: true,
      text: westpac_service_online_ocr_text,
      status: "succeeded",
      message: nil,
      attempted: true,
      error_code: nil
    )

    workbook = with_stubbed_local_ocr(ocr_result) do
      process_upload(tdk_pdf_upload("", filename: "scanned-westpac-service-online.pdf"))
    end

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal "PDF transaction table", workbook.sheet_name
    assert_equal [ "Date", "Category", "Amount", "GST", "Description", "Details", "Balance" ], workbook.processed_headers
    assert_equal 2, workbook.row_count
    assert_equal true, workbook.metadata.fetch("ocr_attempted")
    assert_equal "succeeded", workbook.metadata.fetch("ocr_status")
    assert_equal "local_ocr", workbook.metadata.fetch("ocr_parser")
    assert_equal 2, workbook.metadata.fetch("ocr_row_count")

    deposit_row, withdrawal_row = workbook.rows.ordered.to_a
    assert_equal "2026-05-18", deposit_row.row_data.fetch("Date")
    assert_equal "2000.00", deposit_row.row_data.fetch("Amount")
    assert_equal "-66187.25", deposit_row.row_data.fetch("Balance")
    assert_equal "DEPOSIT SAMPLE VIC", deposit_row.row_data.fetch("Description")

    assert_equal "2026-05-01", withdrawal_row.row_data.fetch("Date")
    assert_equal "-10.00", withdrawal_row.row_data.fetch("Amount")
    assert_equal "-69587.25", withdrawal_row.row_data.fetch("Balance")
    assert_equal "MONTHLY PLAN FEE", withdrawal_row.row_data.fetch("Description")
  end

  test "image based PDF with missing OCR command fails without replacing active workbook" do
    active = create_active_workbook

    with_modified_env("TDK_LOCAL_OCR_ENABLED" => "true", "TDK_LOCAL_OCR_COMMAND" => "tdk-definitely-missing-ocr-command") do
      workbook = process_upload(tdk_pdf_upload("", filename: "scanned-bank-statement.pdf"))

      assert workbook.failed?
      assert_includes workbook.processing_errors, BasTdk::LocalOcr::MISSING_COMMAND_MESSAGE
      assert_equal false, workbook.metadata.fetch("ocr_attempted")
      assert_equal "missing_command", workbook.metadata.fetch("ocr_status")
      assert_equal "processed", active.reload.status
      assert_equal active.id, bas_job.tdk_workbooks.active_processed.first.id
    end
  end

  test "image based PDF with unreliable OCR text fails without replacing active workbook" do
    active = create_active_workbook
    ocr_result = BasTdk::LocalOcr::Result.new(
      success: true,
      text: "Statement summary only\nNo reliable transaction table",
      status: "succeeded",
      message: nil,
      attempted: true,
      error_code: nil
    )

    workbook = with_stubbed_local_ocr(ocr_result) do
      process_upload(tdk_pdf_upload("", filename: "scanned-bank-statement.pdf"))
    end

    assert workbook.failed?
    assert_includes workbook.processing_errors, BasTdk::LocalOcr::UNRELIABLE_MESSAGE
    assert_equal true, workbook.metadata.fetch("ocr_attempted")
    assert_equal "failed", workbook.metadata.fetch("ocr_status")
    assert_equal "processed", active.reload.status
    assert_equal active.id, bas_job.tdk_workbooks.active_processed.first.id
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

  def with_stubbed_local_ocr(result)
    with_stubbed_local_ocr_new(->(**_kwargs) { LocalOcrDouble.new(result) }) do
      yield
    end
  end

  def with_stubbed_local_ocr_new(factory)
    singleton_class = class << BasTdk::LocalOcr; self; end
    singleton_class.alias_method :original_tdk_local_ocr_new, :new
    BasTdk::LocalOcr.define_singleton_method(:new, &factory)
    yield
  ensure
    singleton_class.alias_method :new, :original_tdk_local_ocr_new
    singleton_class.remove_method :original_tdk_local_ocr_new
  end

  def create_active_workbook
    workbook = bas_job.tdk_workbooks.create!(
      status: "processed",
      source_filename: "synthetic-active.xlsx",
      sheet_name: "Bank Report",
      header_row_number: 4,
      original_headers: [ "Date", "Amount", "Description" ],
      processed_headers: [ "Date", "Category", "Amount", "GST", "Description" ],
      row_count: 1,
      version_number: 1,
      processed_at: Time.current,
      processed_by: "tdk-processor-test"
    )
    workbook.rows.create!(
      position: 1,
      source_row_number: 5,
      row_data: {
        "Date" => "2026-01-05",
        "Category" => "",
        "Amount" => "123.45",
        "GST" => "",
        "Description" => "Active synthetic row"
      }
    )
    workbook
  end

  def westpac_pdf_text
    <<~TEXT
      Westpac Business One
      Statement period 05 December 2025 to 05 January 2026
      DATE       TRANSACTION DESCRIPTION                                      DEBIT              CREDIT             BALANCE
      STATEMENT OPENING BALANCE                                                                                       1,647.81
      08/12/25   Deposit-Osko Payment SAMPLE001 SAMPLE CUSTOMER                                   5,049.00           6,696.81
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
      06 MAR     Deposit-Osko Payment SAMPLE CUSTOMER                                        4,373.70           68,371.24
      09 MAR     VISA DEBIT PURCHASE CARD XXXX / SAMPLE PARKING
                 / EFFECTIVE DATE 05 MAR 2026                         3.47                                      68,367.77
      01 APR     Transfer from savings                                                     1,000.00             69,367.77
      TOTALS AT END OF PERIOD
    TEXT
  end

  def westpac_service_online_ocr_text
    <<~TEXT
      Westpac Service Online
      Statement period 01/05/2026 to 31/05/2026
      Date Description Withdrawals Deposits Running Balance
      Opening Balance -$69,597.25
      18/05/2026 DEPOSIT SAMPLE VIC $2,000.00 -$66,187.25
      01/05/2026 MONTHLY PLAN FEE $10.00 -$69,587.25
      Closing Balance -$66,187.25
      Need help? Contact us using Westpac Online.
    TEXT
  end
end
