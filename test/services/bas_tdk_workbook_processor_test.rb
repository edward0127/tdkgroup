require "test_helper"
require "digest"
require_relative "../support/tdk_workbook_helper"

class BasTdkWorkbookProcessorTest < ActiveSupport::TestCase
  include TdkWorkbookHelper

  LocalOcrDouble = Struct.new(:result) do
    def call
      result
    end
  end
  LocalPdfTextExtractorDouble = Struct.new(:result) do
    def call
      result
    end
  end
  PdfParserDouble = Struct.new(:result) do
    def call
      raise result if result.is_a?(StandardError)

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
    assert_equal "detected_header", workbook.metadata.fetch("xlsx_header_strategy")
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
    assert_equal [ "Date", "Category", "Amount", "GST", "Description" ], workbook.processed_headers
    row = workbook.rows.ordered.first
    assert_equal "Meals", row.row_data.fetch("Category")
    assert_equal "GST included", row.row_data.fetch("GST")
    assert_equal "Synthetic lunch", row.row_data.fetch("Description")
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

  test "imports headerless first three column XLSX as Date Amount Description" do
    workbook = process_upload(tdk_xlsx_upload([
      [ 46022, -33.00, "Synthetic supplier payment", "ignored extra 1", "ignored extra 2" ],
      [ 46023, 120.50, "Synthetic customer receipt", "ignored extra 3" ],
      [ 46024, -10.25, "Synthetic card purchase" ]
    ]))

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal "headerless_first_three_columns", workbook.metadata.fetch("xlsx_header_strategy")
    assert_nil workbook.header_row_number
    assert_equal [ "Date", "Amount", "Description" ], workbook.original_headers
    assert_equal [ "Date", "Category", "Amount", "GST", "Description" ], workbook.processed_headers
    assert_equal 3, workbook.row_count
    assert_equal 1, workbook.metadata.fetch("xlsx_headerless_data_start_row")
    assert_equal 3, workbook.metadata.fetch("xlsx_headerless_sample_row_count")
    assert_equal 3, workbook.metadata.fetch("xlsx_headerless_confident_row_count")
    assert_equal 5, workbook.metadata.fetch("xlsx_headerless_detected_column_count")
    assert_equal 2, workbook.metadata.fetch("xlsx_headerless_ignored_column_count")

    rows = workbook.rows.ordered.to_a
    assert_equal [ 1, 2, 3 ], rows.map(&:source_row_number)
    assert_equal [ "2025-12-31", "2026-01-01", "2026-01-02" ], rows.map { |row| row.row_data.fetch("Date") }
    assert_equal [ "-33.00", "120.50", "-10.25" ], rows.map { |row| row.row_data.fetch("Amount") }
    assert_equal [
      "Synthetic supplier payment",
      "Synthetic customer receipt",
      "Synthetic card purchase"
    ], rows.map { |row| row.row_data.fetch("Description") }
    rows.each do |row|
      assert_equal "", row.row_data.fetch("Category")
      assert_equal "", row.row_data.fetch("GST")
      assert_not row.row_data.key?("Details")
    end
  end

  test "imports headerless first three column CSV as Date Amount Description" do
    workbook = process_upload(tdk_csv_upload(<<~CSV))
      2025-07-01,-33.00,Synthetic supplier payment,ignored extra
      2025-07-02,120.50,Synthetic customer receipt,ignored extra
      2025-07-03,-10.25,Synthetic card purchase
    CSV

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal "csv", workbook.metadata.fetch("source_type")
    assert_equal "headerless_first_three_columns", workbook.metadata.fetch("csv_header_strategy")
    assert_nil workbook.header_row_number
    assert_equal [ "Date", "Amount", "Description" ], workbook.original_headers
    assert_equal [ "Date", "Category", "Amount", "GST", "Description" ], workbook.processed_headers
    assert_equal 3, workbook.row_count
    assert_equal 1, workbook.metadata.fetch("csv_data_start_row")
    assert_equal 1, workbook.metadata.fetch("csv_ignored_column_count")

    rows = workbook.rows.ordered.to_a
    assert_equal [ 1, 2, 3 ], rows.map(&:source_row_number)
    assert_equal [ "2025-07-01", "2025-07-02", "2025-07-03" ], rows.map { |row| row.row_data.fetch("Date") }
    assert_equal [ "-33.00", "120.50", "-10.25" ], rows.map { |row| row.row_data.fetch("Amount") }
    assert_equal [
      "Synthetic supplier payment",
      "Synthetic customer receipt",
      "Synthetic card purchase"
    ], rows.map { |row| row.row_data.fetch("Description") }
    rows.each do |row|
      assert_equal "", row.row_data.fetch("Category")
      assert_equal "", row.row_data.fetch("GST")
      assert_not row.row_data.key?("Details")
    end
  end

  test "keeps a headerless transaction when a labelled refund amount contains one signed number" do
    workbook = process_upload(tdk_csv_upload(<<~CSV))
      2025-07-01,-33.00,Synthetic supplier payment
      2025-07-02,120.50,Synthetic customer receipt
      2025-07-03,refund -37.50,Synthetic bank refund
    CSV

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal 3, workbook.row_count
    refund = workbook.rows.ordered.last
    assert_equal "-37.50", refund.row_data.fetch("Amount")
    assert_equal "Synthetic bank refund", refund.row_data.fetch("Description")
  end

  test "infers reordered headerless CSV columns and running balance" do
    workbook = process_upload(tdk_csv_upload(<<~CSV))
      Newest sale,1030.00,2025-01-05,10.00
      Bank fee,1020.00,2025-01-04,-5.00
      Customer payment,1025.00,2025-01-03,20.00
      Supplier payment,1005.00,2025-01-02,-5.00
      Older sale,1010.00,2025-01-01,10.00
    CSV

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal "inferred_columns", workbook.metadata.fetch("csv_header_strategy")
    assert_equal [ "Date", "Category", "Amount", "GST", "Description", "Balance" ], workbook.processed_headers
    assert_equal 5, workbook.row_count

    first = workbook.rows.ordered.first
    assert_equal "2025-01-05", first.row_data.fetch("Date")
    assert_equal "10.00", first.row_data.fetch("Amount")
    assert_equal "Newest sale", first.row_data.fetch("Description")
    assert_equal "1030.00", first.row_data.fetch("Balance")
    assert_equal({ "0" => "description", "1" => "balance", "2" => "date", "3" => "amount" }, workbook.metadata.fetch("csv_column_mapping"))
  end

  test "adds Balance when a headerless fourth column reconciles" do
    workbook = process_upload(tdk_csv_upload(<<~CSV))
      05/01/2025,10.00,Newest sale,1030.00
      04/01/2025,-5.00,Bank fee,1020.00
      03/01/2025,20.00,Customer payment,1025.00
      02/01/2025,-5.00,Supplier payment,1005.00
      01/01/2025,10.00,Older sale,1010.00
    CSV

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal "inferred_columns", workbook.metadata.fetch("csv_header_strategy")
    assert_equal [ "Date", "Category", "Amount", "GST", "Description", "Balance" ], workbook.processed_headers
    assert_equal [ "1030.00", "1020.00", "1025.00", "1005.00", "1010.00" ],
      workbook.rows.ordered.map { |row| row.row_data.fetch("Balance") }
  end

  test "ambiguous headerless debit credit CSV waits for column confirmation" do
    active = create_active_workbook
    workbook = process_upload(tdk_csv_upload(<<~CSV))
      2025-01-01,Opening receipt,,1000.00
      2025-01-02,Supplier payment,10.00,
      2025-01-03,Customer payment,,20.00
      2025-01-04,Bank fee,5.00,
      2025-01-05,Cash receipt,,30.00
    CSV

    assert workbook.needs_mapping?
    assert_equal 0, workbook.row_count
    assert_includes workbook.processing_errors, BasTdk::WorkbookProcessor::COLUMN_MAPPING_REQUIRED_MESSAGE
    detection = workbook.metadata.fetch("column_detection")
    assert_equal "needs_mapping", detection.fetch("decision")
    assert_equal 4, detection.fetch("columns").size
    assert_equal "processed", active.reload.status
    assert_equal active.id, bas_job.tdk_workbooks.active_processed.first.id
  end

  test "confirmed headerless debit credit mapping resumes the same workbook" do
    workbook = process_upload(tdk_csv_upload(<<~CSV))
      2025-01-01,Opening receipt,,1000.00
      2025-01-02,Supplier payment,10.00,
      2025-01-03,Customer payment,,20.00
      2025-01-04,Bank fee,5.00,
      2025-01-05,Cash receipt,,30.00
    CSV
    assert workbook.needs_mapping?

    workbook.update!(
      status: "queued",
      row_errors: [],
      metadata: workbook.metadata.merge(
        "column_mapping_override" => {
          "header_row_number" => nil,
          "data_start_row" => 1,
          "columns" => {
            "0" => "date",
            "1" => "description",
            "2" => "debit",
            "3" => "credit"
          }
        }
      )
    )

    workbook.source_file.open(tmpdir: Rails.root.join("tmp").to_s) do |file|
      BasTdk::WorkbookProcessor.new(
        bas_job: bas_job,
        workbook: workbook,
        source_path: file.path,
        actor_username: "tdk-processor-test"
      ).call
    end

    assert workbook.reload.processed?, workbook.processing_errors.to_sentence
    assert_equal "user_override", workbook.metadata.fetch("csv_header_strategy")
    assert_equal [ "Date", "Category", "Amount", "GST", "Description" ], workbook.processed_headers
    assert_equal [ "1000.00", "-10.00", "20.00", "-5.00", "30.00" ],
      workbook.rows.ordered.map { |row| row.row_data.fetch("Amount") }
  end

  test "imports headered CSV with Date Amount Description" do
    workbook = process_upload(tdk_csv_upload(<<~CSV))
      Date,Amount,Description
      01/07/2025,-33.00,Synthetic supplier payment
      02/07/2025,120.50,Synthetic customer receipt
    CSV

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal "detected_header", workbook.metadata.fetch("csv_header_strategy")
    assert_equal 1, workbook.metadata.fetch("csv_header_row_number")
    assert_equal 2, workbook.metadata.fetch("csv_data_start_row")
    assert_equal [ "Date", "Category", "Amount", "GST", "Description" ], workbook.processed_headers
    assert_equal 2, workbook.row_count

    rows = workbook.rows.ordered.to_a
    assert_equal [ "2025-07-01", "2025-07-02" ], rows.map { |row| row.row_data.fetch("Date") }
    assert_equal [ "-33.00", "120.50" ], rows.map { |row| row.row_data.fetch("Amount") }
    assert_equal [ "", "" ], rows.map { |row| row.row_data.fetch("Category") }
    assert_equal [ "", "" ], rows.map { |row| row.row_data.fetch("GST") }
  end

  test "imports CSV month name dates as ISO dates" do
    workbook = process_upload(tdk_csv_upload(<<~CSV))
      Date,Amount,Account Number,Transaction Type,Transaction Details,Balance,Category,Processed On
      23 Jun 26,342.30,123456,SYNTHETIC CREDIT,Synthetic government payment,2961.92,Synthetic category,23 Jun 26
      1 Jul 26,-42.42,123456,SYNTHETIC DEBIT,Synthetic card purchase,2919.50,Synthetic category,1 Jul 26
    CSV

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal "detected_header", workbook.metadata.fetch("csv_header_strategy")

    rows = workbook.rows.ordered.to_a
    assert_equal [ "2026-06-23", "2026-07-01" ], rows.map { |row| row.row_data.fetch("Date") }
    assert_equal [ "342.30", "-42.42" ], rows.map { |row| row.row_data.fetch("Amount") }
    assert_equal [ "2961.92", "2919.50" ], rows.map { |row| row.row_data.fetch("Balance") }
    assert_equal [ "Synthetic category", "Synthetic category" ], rows.map { |row| row.row_data.fetch("Category") }
    assert_equal [ "Synthetic government payment", "Synthetic card purchase" ], rows.map { |row| row.row_data.fetch("Description") }
    assert_equal [ "123456", "123456" ], rows.map { |row| row.row_data.fetch("Account Number") }
    assert_equal [ "SYNTHETIC CREDIT", "SYNTHETIC DEBIT" ], rows.map { |row| row.row_data.fetch("Transaction Type") }
  end

  test "imports CSV with debit credit balance columns" do
    workbook = process_upload(tdk_csv_upload(<<~CSV))
      Date,Description,Debit,Credit,Balance
      01/07/2025,Synthetic debit,33.00,,966.00
      02/07/2025,Synthetic credit,,120.50,1086.50
    CSV

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal "detected_header", workbook.metadata.fetch("csv_header_strategy")
    assert_equal [ "Date", "Category", "Amount", "GST", "Description", "Balance" ], workbook.processed_headers

    debit_row, credit_row = workbook.rows.ordered.to_a
    assert_equal "-33.00", debit_row.row_data.fetch("Amount")
    assert_equal "120.50", credit_row.row_data.fetch("Amount")
    assert_equal "966.00", debit_row.row_data.fetch("Balance")
    assert_equal "1086.50", credit_row.row_data.fetch("Balance")
    refute_includes workbook.processed_headers, "Debit"
    refute_includes workbook.processed_headers, "Credit"
  end

  test "canonicalises narrative debit credit and balance headers while preserving extras" do
    workbook = process_upload(tdk_xlsx_upload([
      [ "Bank Account", "Date", "Narrative", "Debit Amount", "Credit Amount", "Balance", nil, "Serial" ],
      [ "33005436007", Date.new(2026, 3, 30), "EFTPOS debit", 1.49, nil, 771.50, "software", "ABC-1" ],
      [ "33005436007", Date.new(2026, 3, 29), "Deposit payment", nil, 3_000, 3_771.50, "income", "ABC-2" ]
    ], accounting_format_columns: [ 4, 5, 6 ]))

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal "detected_header", workbook.metadata.fetch("xlsx_header_strategy")
    assert_equal [
      "Date", "Category", "Amount", "GST", "Description", "Balance", "Details", "Bank Account", "Serial"
    ], workbook.processed_headers

    debit_row, credit_row = workbook.rows.ordered.to_a
    assert_equal "-1.49", debit_row.row_data.fetch("Amount")
    assert_equal "3000.00", credit_row.row_data.fetch("Amount")
    assert_equal "EFTPOS debit", debit_row.row_data.fetch("Description")
    assert_equal "771.50", debit_row.row_data.fetch("Balance")
    assert_equal "software", debit_row.row_data.fetch("Details")
    assert_equal "33005436007", debit_row.row_data.fetch("Bank Account")
    assert_equal "ABC-1", debit_row.row_data.fetch("Serial")
    refute_includes workbook.processed_headers, "Debit"
    refute_includes workbook.processed_headers, "Credit"
    refute_includes workbook.processed_headers, "Narrative"
  end

  test "canonicalises and orders arbitrary header aliases with a direct amount" do
    workbook = process_upload(tdk_csv_upload(<<~CSV))
      Running Balance,Narrative,Transaction Amount,Posting Date,Bank Account
      966.00,Synthetic supplier payment,-33.00,01/07/2025,Everyday account
      1086.50,Synthetic customer receipt,120.50,02/07/2025,Everyday account
    CSV

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal [ "Date", "Category", "Amount", "GST", "Description", "Balance", "Bank Account" ], workbook.processed_headers

    rows = workbook.rows.ordered.to_a
    assert_equal [ "2025-07-01", "2025-07-02" ], rows.map { |row| row.row_data.fetch("Date") }
    assert_equal [ "-33.00", "120.50" ], rows.map { |row| row.row_data.fetch("Amount") }
    assert_equal [ "966.00", "1086.50" ], rows.map { |row| row.row_data.fetch("Balance") }
    assert_equal [ "Synthetic supplier payment", "Synthetic customer receipt" ], rows.map { |row| row.row_data.fetch("Description") }
  end

  test "recognises common description aliases and currency-qualified amount and balance headers" do
    %w[Payee Merchant].each_with_index do |description_header, index|
      workbook = process_upload(tdk_csv_upload(<<~CSV))
        Posting Date,Transaction Amount (AUD),#{description_header},Current Balance (AUD)
        0#{index + 1}/07/2025,-12.50,Synthetic #{description_header.downcase},987.50
      CSV

      assert workbook.processed?, "#{description_header}: #{workbook.processing_errors.to_sentence}"
      row = workbook.rows.ordered.first
      assert_equal "-12.50", row.row_data.fetch("Amount")
      assert_equal "987.50", row.row_data.fetch("Balance")
      assert_equal "Synthetic #{description_header.downcase}", row.row_data.fetch("Description")
    end
  end

  test "recognises debit amt and DR CR split amount aliases" do
    workbook = process_upload(tdk_csv_upload(<<~CSV))
      Date,Debit Amt (AUD),CR (AUD),Merchant,Running Balance (AUD)
      01/07/2025,12.50,,Synthetic cafe,987.50
      02/07/2025,,25.00,Synthetic receipt,1012.50
    CSV

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal [ "-12.50", "25.00" ], workbook.rows.ordered.map { |row| row.row_data.fetch("Amount") }
    assert_equal [ "987.50", "1012.50" ], workbook.rows.ordered.map { |row| row.row_data.fetch("Balance") }
  end

  test "confirmed mapping normalises two digit and slash ISO dates without dropping rows" do
    workbook = mapping_workbook(
      version_number: 1,
      mapping: { "0" => "date", "1" => "amount", "2" => "description" }
    )

    process_existing_upload(workbook, tdk_csv_upload(<<~CSV))
      05/01/25,10.00,Two digit year
      2025/01/06,-4.50,Slash ISO date
    CSV

    assert workbook.reload.processed?, workbook.processing_errors.to_sentence
    assert_equal 2, workbook.row_count
    assert_equal [ "2025-01-05", "2025-01-06" ], workbook.rows.ordered.map { |row| row.row_data.fetch("Date") }
  end

  test "confirmed mapping returns to review when a transaction-like row cannot be parsed" do
    active = create_active_workbook
    workbook = mapping_workbook(
      version_number: 2,
      mapping: { "0" => "date", "1" => "amount", "2" => "description" }
    )

    process_existing_upload(workbook, tdk_csv_upload(<<~CSV))
      05/01/25,10.00,Valid transaction
      not-a-date,12.00,Invalid transaction
    CSV

    assert workbook.reload.needs_mapping?
    assert_equal 0, workbook.row_count
    assert_includes workbook.processing_errors.join(" "), BasTdk::WorkbookProcessor::MAPPED_ROW_ERROR
    assert_includes workbook.processing_errors.join(" "), "Source rows: 2"
    assert_equal "processed", active.reload.status
    assert_equal active.id, bas_job.tdk_workbooks.active_processed.first.id
  end

  test "confirmed mapping that yields no rows returns to review instead of falling back to legacy columns" do
    active = create_active_workbook
    workbook = mapping_workbook(
      version_number: 2,
      mapping: { "3" => "date", "4" => "amount", "5" => "description" }
    )

    process_existing_upload(workbook, tdk_csv_upload("2025-01-05,10.00,Would match legacy,,,\n"))

    assert workbook.reload.needs_mapping?
    assert_includes workbook.processing_errors, BasTdk::WorkbookProcessor::CONFIRMED_COLUMN_MAPPING_ERROR
    assert_equal "processed", active.reload.status
    assert_equal active.id, bas_job.tdk_workbooks.active_processed.first.id
  end

  test "confirmed mapping rejects duplicate debit roles" do
    workbook = mapping_workbook(
      version_number: 1,
      mapping: { "0" => "date", "1" => "description", "2" => "debit", "3" => "debit" }
    )

    process_existing_upload(workbook, tdk_csv_upload("2025-01-05,Synthetic payment,10.00,20.00\n"))

    assert workbook.reload.needs_mapping?
    assert_includes workbook.processing_errors, BasTdk::WorkbookProcessor::CONFIRMED_COLUMN_MAPPING_ERROR
  end

  test "header-only workbook fails without replacing the active processed workbook" do
    active = create_active_workbook

    workbook = process_upload(tdk_csv_upload("Date,Amount,Description\n"))

    assert workbook.failed?
    assert_equal 0, workbook.row_count
    assert_includes workbook.processing_errors, BasTdk::WorkbookProcessor::EMPTY_TRANSACTION_ERROR
    assert_equal "processed", active.reload.status
    assert_equal active.id, bas_job.tdk_workbooks.active_processed.first.id
  end

  test "recognised headers with only a footer fail without replacing the active workbook" do
    active = create_active_workbook

    workbook = process_upload(tdk_csv_upload(<<~CSV))
      Date,Amount,Description
      ,,Closing balance follows
    CSV

    assert workbook.failed?
    assert_equal 0, workbook.row_count
    assert_includes workbook.processing_errors, BasTdk::WorkbookProcessor::EMPTY_TRANSACTION_ERROR
    assert_equal "processed", active.reload.status
    assert_equal active.id, bas_job.tdk_workbooks.active_processed.first.id
  end

  test "an older workbook completing later cannot replace a newer processed version" do
    original = create_active_workbook
    older = bas_job.tdk_workbooks.create!(
      status: "queued",
      source_filename: "older.csv",
      version_number: 2,
      processed_by: "tdk-processor-test"
    )
    newer = bas_job.tdk_workbooks.create!(
      status: "queued",
      source_filename: "newer.csv",
      version_number: 3,
      processed_by: "tdk-processor-test"
    )

    process_existing_upload(newer, tdk_csv_upload(<<~CSV, filename: "newer.csv"))
      Date,Amount,Description
      03/01/2025,30.00,Newest transaction
    CSV
    process_existing_upload(older, tdk_csv_upload(<<~CSV, filename: "older.csv"))
      Date,Amount,Description
      02/01/2025,20.00,Older transaction
    CSV

    assert newer.reload.processed?
    assert older.reload.superseded?
    assert_equal newer.id, older.metadata.fetch("superseded_by_workbook_id")
    assert_equal newer.version_number, older.metadata.fetch("superseded_by_version_number")
    assert original.reload.superseded?
    assert_equal newer.id, bas_job.tdk_workbooks.active_processed.first.id
    assert_equal "Newest transaction", bas_job.tdk_workbooks.active_processed.first.rows.ordered.first.row_data.fetch("Description")
  end

  test "sparse far-right cells do not expand mapped or exact-header processing" do
    requested_columns = []
    requested_rows = []
    cells = {
      [ 1, 1 ] => "Date",
      [ 1, 2 ] => "Amount",
      [ 1, 3 ] => "Description",
      [ 2, 1 ] => "05/01/2025",
      [ 2, 2 ] => "10.00",
      [ 2, 3 ] => "Synthetic transaction",
      [ 1_048_576, 16_384 ] => "stray XFD value"
    }
    sheet = Object.new
    sheet.define_singleton_method(:last_row) { 1_048_576 }
    sheet.define_singleton_method(:last_column) { 16_384 }
    sheet.define_singleton_method(:cells_by_row) do
      {
        1 => { 1 => "Date", 2 => "Amount", 3 => "Description" },
        2 => { 1 => "05/01/2025", 2 => "10.00", 3 => "Synthetic transaction" },
        1_048_576 => { 16_384 => "stray XFD value" }
      }
    end
    sheet.define_singleton_method(:cell) do |row, column|
      requested_rows << row
      requested_columns << column
      cells[[ row, column ]]
    end
    processor = BasTdk::WorkbookProcessor.new(
      bas_job: bas_job,
      actor_username: "tdk-processor-test"
    )

    mapped = processor.send(
      :build_column_mapped_workbook,
      sheet: sheet,
      sheet_name: "Sparse mapped sheet",
      header_row_number: 1,
      data_start_row: 2,
      mapping: { "0" => "date", "1" => "amount", "2" => "description" }
    )
    assert_equal 3, requested_columns.max
    assert_equal 1, mapped.rows.size

    requested_columns.clear
    parsed = processor.send(
      :parse_statement_sheet,
      sheet: sheet,
      sheet_name: "Sparse exact-header sheet",
      metadata_prefix: "xlsx"
    )
    assert_operator requested_columns.max, :<=, BasTdk::WorkbookProcessor::MAX_STATEMENT_COLUMNS
    assert_operator parsed.original_headers.size, :<=, BasTdk::WorkbookProcessor::MAX_STATEMENT_COLUMNS
    assert_equal 1, parsed.rows.size
    assert_operator requested_rows.uniq.size, :<, 30
    refute_includes parsed.processed_headers, "stray XFD value"
  end

  test "headerless CSV can start after leading blank rows" do
    workbook = process_upload(tdk_csv_upload(<<~CSV))


      2025-07-01,-33.00,Synthetic payment
    CSV

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal "headerless_first_three_columns", workbook.metadata.fetch("csv_header_strategy")
    assert_equal 3, workbook.metadata.fetch("csv_data_start_row")
    assert_equal 1, workbook.row_count

    row = workbook.rows.ordered.first
    assert_equal 1, row.position
    assert_equal 3, row.source_row_number
    assert_equal "2025-07-01", row.row_data.fetch("Date")
    assert_equal "-33.00", row.row_data.fetch("Amount")
    assert_equal "Synthetic payment", row.row_data.fetch("Description")
  end

  test "does not use headerless fallback for arbitrary three column CSV" do
    workbook = process_upload(tdk_csv_upload(<<~CSV))
      Synthetic Business,Statement,Notes
      Name,Project,Something
    CSV

    assert workbook.failed?
    assert_equal 0, workbook.row_count
    assert_includes workbook.processing_errors, BasTdk::WorkbookProcessor::FRIENDLY_HEADER_ERROR
  end

  test "CSV handles BOM and quoted comma descriptions" do
    workbook = process_upload(tdk_csv_upload("\xEF\xBB\xBFDate,Amount,Description\n2025-07-01,-33.00,\"Synthetic supplier, with comma\"\n"))

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal "UTF-8", workbook.metadata.fetch("csv_encoding")
    assert_equal "Synthetic supplier, with comma", workbook.rows.ordered.first.row_data.fetch("Description")
  end

  test "CSV handles accounting parentheses amounts" do
    workbook = process_upload(tdk_csv_upload(<<~CSV))
      Date,Amount,Description
      2025-07-01,"($33.00)",Synthetic payment
    CSV

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal "-33.00", workbook.rows.ordered.first.row_data.fetch("Amount")
  end

  test "headerless first three column XLSX can start after leading blank rows" do
    workbook = process_upload(tdk_xlsx_upload([
      [],
      [],
      [ 46022, -33.00, "Synthetic payment" ]
    ]))

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal "headerless_first_three_columns", workbook.metadata.fetch("xlsx_header_strategy")
    assert_equal 3, workbook.metadata.fetch("xlsx_headerless_data_start_row")
    assert_equal 1, workbook.row_count

    row = workbook.rows.ordered.first
    assert_equal 1, row.position
    assert_equal 3, row.source_row_number
    assert_equal "2025-12-31", row.row_data.fetch("Date")
    assert_equal "-33.00", row.row_data.fetch("Amount")
    assert_equal "Synthetic payment", row.row_data.fetch("Description")
  end

  test "does not use headerless fallback for arbitrary three column spreadsheet" do
    workbook = process_upload(tdk_xlsx_upload([
      [ "Synthetic Business", "Statement", "No transaction data" ],
      [ "Name", "Project", "Notes" ]
    ]))

    assert workbook.failed?
    assert_equal 0, workbook.row_count
    assert_includes workbook.processing_errors, BasTdk::WorkbookProcessor::FRIENDLY_HEADER_ERROR
  end

  test "headered XLSX still uses detected headers instead of headerless fallback" do
    workbook = process_upload(tdk_xlsx_upload([
      [ "Synthetic Business Pty Ltd" ],
      [ "Statement period", "1 Jan 2026 to 31 Mar 2026" ],
      [],
      [ "Date", "Amount", "Description", nil, nil ],
      [ 46022, -33.00, "Synthetic supplier payment", "Card ref 123", "Terminal 9" ],
      [ 46023, 120.50, "Synthetic customer receipt" ]
    ]))

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal "detected_header", workbook.metadata.fetch("xlsx_header_strategy")
    assert_equal 4, workbook.header_row_number
    assert_equal [ "Date", "Amount", "Description" ], workbook.original_headers.first(3)
    assert_equal [ "Date", "Category", "Amount", "GST", "Description", "Details" ], workbook.processed_headers
    assert_equal 2, workbook.row_count
    assert_equal "Card ref 123 | Terminal 9", workbook.rows.ordered.first.row_data.fetch("Details")
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

  test "stores text based PDF debit column amounts as negative with continuation lines" do
    workbook = process_upload(tdk_pdf_upload(separate_debit_credit_pdf_text, filename: "synthetic-separate-columns.pdf"))

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal 3, workbook.row_count

    credit_row, first_debit_row, second_debit_row = workbook.rows.ordered.to_a
    assert_equal "265.86", credit_row.row_data.fetch("Amount")
    assert_equal "1178.79", credit_row.row_data.fetch("Balance")
    assert_equal "-9.10", first_debit_row.row_data.fetch("Amount")
    assert_equal "1169.69", first_debit_row.row_data.fetch("Balance")
    assert_equal "-14.50", second_debit_row.row_data.fetch("Amount")
    assert_equal "1155.19", second_debit_row.row_data.fetch("Balance")

    imported_text = workbook.rows.ordered.map { |row| row.row_data.fetch("Description") }.join(" ")
    refute_includes imported_text, "blank"
    refute_includes imported_text, "TOTALS AT END OF PAGE"
  end

  test "stores repeated shifted PDF debit credit rows with current header positions" do
    workbook = process_upload(tdk_pdf_upload(repeated_shifted_debit_credit_pdf_text, filename: "synthetic-shifted-columns.pdf"))

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal 5, workbook.row_count

    rows = workbook.rows.ordered.to_a.map(&:row_data)
    assert_equal [ "125.00", "-33.00", "-44.00", "175.00", "-11.50" ], rows.map { |row| row.fetch("Amount") }
    assert_equal [ "2125.00", "2092.00", "2048.00", "2223.00", "2211.50" ], rows.map { |row| row.fetch("Balance") }

    imported_text = rows.map { |row| row.fetch("Description") }.join(" ")
    refute_includes imported_text, "OPENING BALANCE"
    refute_includes imported_text, "$"
    refute_match(/\bblank\b/i, imported_text)
    rows.each { |row| refute_match(/\b(?:CR|DR)\z/i, row.fetch("Description")) }
  end

  test "low recall readable PDF uses better local layout text parse without OCR" do
    low_reader_parse = parsed_pdf_statement(row_count: 2, candidate_count: 40, quality: "low_recall")
    layout_parse = parsed_pdf_statement(row_count: 35, candidate_count: 35, quality: "good")
    layout_result = BasTdk::LocalPdfTextExtractor::Result.new(
      success: true,
      text: "layout text should not be stored",
      status: "succeeded",
      message: nil,
      attempted: true,
      error_code: nil
    )
    ocr_called = false

    workbook = with_stubbed_pdf_parser_new(->(**kwargs) {
      PdfParserDouble.new(kwargs[:text].present? ? layout_parse : low_reader_parse)
    }) do
      with_stubbed_local_pdf_text_extractor(layout_result) do
        with_stubbed_local_ocr_new(->(**_kwargs) {
          ocr_called = true
          LocalOcrDouble.new(nil)
        }) do
          process_upload(tdk_pdf_upload("synthetic low recall reader text", filename: "synthetic-low-recall.pdf"))
        end
      end
    end

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal 35, workbook.row_count
    assert_equal "pdf_text_layout", workbook.metadata.fetch("pdf_parse_strategy")
    assert_equal 35, workbook.metadata.fetch("pdf_parse_row_count")
    assert_equal 35, workbook.metadata.fetch("pdf_parse_candidate_count")
    assert_equal "good", workbook.metadata.fetch("pdf_parse_quality")
    assert_equal true, workbook.metadata.fetch("pdf_text_layout_attempted")
    assert_equal "succeeded", workbook.metadata.fetch("pdf_text_layout_status")
    assert_equal "parsed", workbook.metadata.fetch("pdf_text_layout_parse_status")
    assert_equal 2, workbook.metadata.fetch("pdf_reader_row_count")
    assert_equal 35, workbook.metadata.fetch("pdf_text_layout_row_count")
    assert_equal false, workbook.metadata.fetch("ocr_attempted")
    refute ocr_called
  end

  test "readable PDF compares reader and layout candidates and selects better layout parse" do
    reader_parse = parsed_pdf_statement(
      row_count: 7,
      candidate_count: 7,
      quality: "good",
      balance_continuity_check_count: 7,
      balance_continuity_mismatch_count: 1,
      balance_continuity_mismatch_ratio: 0.1429
    )
    layout_parse = parsed_pdf_statement(
      row_count: 12,
      candidate_count: 12,
      quality: "good",
      balance_continuity_check_count: 12,
      balance_continuity_mismatch_count: 0,
      balance_continuity_mismatch_ratio: 0.0
    )
    layout_result = BasTdk::LocalPdfTextExtractor::Result.new(
      success: true,
      text: "layout text should not be stored",
      status: "succeeded",
      message: nil,
      attempted: true,
      error_code: nil
    )
    ocr_called = false

    workbook = with_stubbed_pdf_parser_new(->(**kwargs) {
      PdfParserDouble.new(kwargs[:text].present? ? layout_parse : reader_parse)
    }) do
      with_stubbed_local_pdf_text_extractor(layout_result) do
        with_stubbed_local_ocr_new(->(**_kwargs) {
          ocr_called = true
          LocalOcrDouble.new(nil)
        }) do
          process_upload(tdk_pdf_upload("synthetic readable reader text", filename: "synthetic-compare-layout.pdf"))
        end
      end
    end

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal 12, workbook.row_count
    assert_equal "pdf_text_layout", workbook.metadata.fetch("pdf_parse_strategy")
    assert_equal 7, workbook.metadata.fetch("pdf_reader_row_count")
    assert_equal 7, workbook.metadata.fetch("pdf_reader_candidate_count")
    assert_equal "good", workbook.metadata.fetch("pdf_reader_quality")
    assert_equal 1, workbook.metadata.fetch("pdf_reader_balance_continuity_mismatch_count")
    assert_equal 12, workbook.metadata.fetch("pdf_text_layout_row_count")
    assert_equal 12, workbook.metadata.fetch("pdf_text_layout_candidate_count")
    assert_equal "good", workbook.metadata.fetch("pdf_text_layout_quality")
    assert_equal 0, workbook.metadata.fetch("pdf_text_layout_balance_continuity_mismatch_count")
    assert_equal false, workbook.metadata.fetch("ocr_attempted")
    refute ocr_called
  end

  test "readable PDF keeps reader parse when layout extractor is missing and reader is acceptable" do
    reader_parse = parsed_pdf_statement(row_count: 7, candidate_count: 7, quality: "good")
    missing_layout_result = BasTdk::LocalPdfTextExtractor::Result.new(
      success: false,
      text: nil,
      status: "missing_command",
      message: BasTdk::LocalPdfTextExtractor::MISSING_COMMAND_MESSAGE,
      attempted: false,
      error_code: :missing_command
    )
    ocr_called = false

    workbook = with_stubbed_pdf_parser_new(->(**_kwargs) { PdfParserDouble.new(reader_parse) }) do
      with_stubbed_local_pdf_text_extractor(missing_layout_result) do
        with_stubbed_local_ocr_new(->(**_kwargs) {
          ocr_called = true
          LocalOcrDouble.new(nil)
        }) do
          process_upload(tdk_pdf_upload("synthetic good reader text", filename: "synthetic-reader-without-layout.pdf"))
        end
      end
    end

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal 7, workbook.row_count
    assert_equal "pdf_reader", workbook.metadata.fetch("pdf_parse_strategy")
    assert_equal "good", workbook.metadata.fetch("pdf_parse_quality")
    assert_equal 7, workbook.metadata.fetch("pdf_reader_row_count")
    assert_equal false, workbook.metadata.fetch("pdf_text_layout_attempted")
    assert_equal "missing_command", workbook.metadata.fetch("pdf_text_layout_status")
    assert_equal false, workbook.metadata.fetch("ocr_attempted")
    refute ocr_called
  end

  test "layout candidate is not selected only because it has more rows when continuity is poor" do
    reader_parse = parsed_pdf_statement(row_count: 7, candidate_count: 7, quality: "good")
    layout_parse = parsed_pdf_statement(
      row_count: 12,
      candidate_count: 12,
      quality: "poor_balance_continuity",
      balance_continuity_check_count: 12,
      balance_continuity_mismatch_count: 5,
      balance_continuity_mismatch_ratio: 0.4167,
      quality_score: -100
    )
    layout_result = BasTdk::LocalPdfTextExtractor::Result.new(
      success: true,
      text: "layout text should not be stored",
      status: "succeeded",
      message: nil,
      attempted: true,
      error_code: nil
    )
    ocr_called = false

    workbook = with_stubbed_pdf_parser_new(->(**kwargs) {
      PdfParserDouble.new(kwargs[:text].present? ? layout_parse : reader_parse)
    }) do
      with_stubbed_local_pdf_text_extractor(layout_result) do
        with_stubbed_local_ocr_new(->(**_kwargs) {
          ocr_called = true
          LocalOcrDouble.new(nil)
        }) do
          process_upload(tdk_pdf_upload("synthetic noisy layout text", filename: "synthetic-noisy-layout.pdf"))
        end
      end
    end

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal 7, workbook.row_count
    assert_equal "pdf_reader", workbook.metadata.fetch("pdf_parse_strategy")
    assert_equal "poor_balance_continuity", workbook.metadata.fetch("pdf_text_layout_quality")
    assert_equal 12, workbook.metadata.fetch("pdf_text_layout_row_count")
    assert_equal 5, workbook.metadata.fetch("pdf_text_layout_balance_continuity_mismatch_count")
    assert_equal false, workbook.metadata.fetch("ocr_attempted")
    refute ocr_called
  end

  test "readable PDF selects best local text mode when layout mode is poor" do
    reader_parse = parsed_pdf_statement(
      row_count: 7,
      candidate_count: 7,
      quality: "poor_balance_continuity",
      balance_continuity_mismatch_count: 4,
      balance_continuity_mismatch_ratio: 0.5714
    )
    layout_parse = parsed_pdf_statement(
      row_count: 5,
      candidate_count: 5,
      quality: "poor_balance_continuity",
      balance_continuity_mismatch_count: 4,
      balance_continuity_mismatch_ratio: 0.8
    )
    raw_parse = parsed_pdf_statement(
      row_count: 12,
      candidate_count: 12,
      quality: "good",
      statement_reconciliation_status: "matched",
      opening_balance_present: true,
      closing_balance_present: true
    )
    fixed_parse = parsed_pdf_statement(
      row_count: 10,
      candidate_count: 10,
      quality: "poor_balance_continuity",
      balance_continuity_mismatch_count: 5,
      balance_continuity_mismatch_ratio: 0.5
    )
    extractor_results = {
      layout: pdf_text_extraction_result(mode: :layout, text: "layout synthetic text"),
      layout_nopgbrk: pdf_text_extraction_result(mode: :layout_nopgbrk, success: false, status: "failed", error_code: :failed),
      raw: pdf_text_extraction_result(mode: :raw, text: "raw synthetic text"),
      table: pdf_text_extraction_result(mode: :table, success: false, status: "unsupported", error_code: :unsupported),
      fixed: pdf_text_extraction_result(mode: :fixed, text: "fixed synthetic text")
    }
    parsed_by_text = {
      "layout synthetic text" => layout_parse,
      "raw synthetic text" => raw_parse,
      "fixed synthetic text" => fixed_parse
    }
    ocr_called = false

    workbook = with_stubbed_pdf_parser_new(->(**kwargs) {
      PdfParserDouble.new(kwargs[:path].present? ? reader_parse : parsed_by_text.fetch(kwargs[:text]))
    }) do
      with_stubbed_local_pdf_text_extractor_results(extractor_results) do
        with_stubbed_local_ocr_new(->(**_kwargs) {
          ocr_called = true
          LocalOcrDouble.new(nil)
        }) do
          process_upload(tdk_pdf_upload("synthetic readable reader text", filename: "synthetic-mode-selection.pdf"))
        end
      end
    end

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal 12, workbook.row_count
    assert_equal "pdf_text_raw", workbook.metadata.fetch("pdf_parse_strategy")
    assert_equal "poor_balance_continuity", workbook.metadata.fetch("pdf_reader_quality")
    assert_equal "poor_balance_continuity", workbook.metadata.fetch("pdf_text_layout_quality")
    assert_equal "good", workbook.metadata.fetch("pdf_text_raw_quality")
    assert_equal "matched", workbook.metadata.fetch("pdf_text_raw_statement_reconciliation_status")
    assert_equal "unsupported", workbook.metadata.fetch("pdf_text_table_status")
    assert_equal "succeeded", workbook.metadata.fetch("pdf_text_fixed_status")
    assert_equal false, workbook.metadata.fetch("ocr_attempted")
    refute ocr_called
  end

  test "does not fail when one local text mode is poor but another mode is reliable" do
    reader_parse = parsed_pdf_statement(row_count: 6, candidate_count: 6, quality: "poor_balance_continuity")
    layout_parse = parsed_pdf_statement(row_count: 6, candidate_count: 6, quality: "poor_balance_continuity")
    nopgbrk_parse = parsed_pdf_statement(
      row_count: 9,
      candidate_count: 9,
      quality: "good",
      statement_reconciliation_status: "matched",
      opening_balance_present: true,
      closing_balance_present: true
    )
    extractor_results = {
      layout: pdf_text_extraction_result(mode: :layout, text: "layout poor text"),
      layout_nopgbrk: pdf_text_extraction_result(mode: :layout_nopgbrk, text: "layout nopgbrk reliable text"),
      raw: pdf_text_extraction_result(mode: :raw, success: false, status: "failed", error_code: :failed),
      table: pdf_text_extraction_result(mode: :table, success: false, status: "unsupported", error_code: :unsupported),
      fixed: pdf_text_extraction_result(mode: :fixed, success: false, status: "failed", error_code: :failed)
    }
    parsed_by_text = {
      "layout poor text" => layout_parse,
      "layout nopgbrk reliable text" => nopgbrk_parse
    }
    ocr_called = false

    workbook = with_stubbed_pdf_parser_new(->(**kwargs) {
      PdfParserDouble.new(kwargs[:path].present? ? reader_parse : parsed_by_text.fetch(kwargs[:text]))
    }) do
      with_stubbed_local_pdf_text_extractor_results(extractor_results) do
        with_stubbed_local_ocr_new(->(**_kwargs) {
          ocr_called = true
          LocalOcrDouble.new(nil)
        }) do
          process_upload(tdk_pdf_upload("synthetic readable reader text", filename: "synthetic-nopgbrk-selection.pdf"))
        end
      end
    end

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal 9, workbook.row_count
    assert_equal "pdf_text_layout_nopgbrk", workbook.metadata.fetch("pdf_parse_strategy")
    assert_equal "poor_balance_continuity", workbook.metadata.fetch("pdf_text_layout_quality")
    assert_equal "good", workbook.metadata.fetch("pdf_text_layout_nopgbrk_quality")
    assert_equal false, workbook.metadata.fetch("ocr_attempted")
    refute ocr_called
  end

  test "fails safely only after all text modes are unavailable or unreliable" do
    active = create_active_workbook
    reader_parse = parsed_pdf_statement(row_count: 7, candidate_count: 7, quality: "poor_balance_continuity")
    layout_parse = parsed_pdf_statement(row_count: 5, candidate_count: 5, quality: "poor_balance_continuity")
    raw_parse = parsed_pdf_statement(row_count: 4, candidate_count: 40, quality: "low_recall")
    extractor_results = {
      layout: pdf_text_extraction_result(mode: :layout, text: "layout unreliable text"),
      layout_nopgbrk: pdf_text_extraction_result(mode: :layout_nopgbrk, success: false, status: "failed", error_code: :failed),
      raw: pdf_text_extraction_result(mode: :raw, text: "raw low recall text"),
      table: pdf_text_extraction_result(mode: :table, success: false, status: "unsupported", error_code: :unsupported),
      fixed: pdf_text_extraction_result(mode: :fixed, success: false, status: "failed", error_code: :failed)
    }
    parsed_by_text = {
      "layout unreliable text" => layout_parse,
      "raw low recall text" => raw_parse
    }
    ocr_called = false

    workbook = with_stubbed_pdf_parser_new(->(**kwargs) {
      PdfParserDouble.new(kwargs[:path].present? ? reader_parse : parsed_by_text.fetch(kwargs[:text]))
    }) do
      with_stubbed_local_pdf_text_extractor_results(extractor_results) do
        with_stubbed_local_ocr_new(->(**_kwargs) {
          ocr_called = true
          LocalOcrDouble.new(nil)
        }) do
          process_upload(tdk_pdf_upload("synthetic readable reader text", filename: "synthetic-all-unreliable.pdf"))
        end
      end
    end

    assert workbook.failed?
    assert_equal 0, workbook.row_count
    assert_includes workbook.processing_errors, BasTdk::WorkbookProcessor::READABLE_PDF_UNRELIABLE_MESSAGE
    assert_equal "poor_balance_continuity", workbook.metadata.fetch("pdf_reader_quality")
    assert_equal "poor_balance_continuity", workbook.metadata.fetch("pdf_text_layout_quality")
    assert_equal "low_recall", workbook.metadata.fetch("pdf_text_raw_quality")
    assert_equal "unsupported", workbook.metadata.fetch("pdf_text_table_status")
    assert_equal false, workbook.metadata.fetch("ocr_attempted")
    refute ocr_called
    assert_equal "processed", active.reload.status
    assert_equal active.id, bas_job.tdk_workbooks.active_processed.first.id
  end

  test "does not select higher row count candidate when statement reconciliation mismatches" do
    reader_parse = parsed_pdf_statement(
      row_count: 7,
      candidate_count: 7,
      quality: "good",
      statement_reconciliation_status: "matched",
      opening_balance_present: true,
      closing_balance_present: true
    )
    raw_parse = parsed_pdf_statement(
      row_count: 12,
      candidate_count: 12,
      quality: "statement_reconciliation_mismatch",
      statement_reconciliation_status: "mismatch",
      statement_reconciliation_delta_mismatch: "25.00",
      opening_balance_present: true,
      closing_balance_present: true
    )
    extractor_results = {
      layout: pdf_text_extraction_result(mode: :layout, success: false, status: "failed", error_code: :failed),
      layout_nopgbrk: pdf_text_extraction_result(mode: :layout_nopgbrk, success: false, status: "failed", error_code: :failed),
      raw: pdf_text_extraction_result(mode: :raw, text: "raw mismatch text"),
      table: pdf_text_extraction_result(mode: :table, success: false, status: "unsupported", error_code: :unsupported),
      fixed: pdf_text_extraction_result(mode: :fixed, success: false, status: "failed", error_code: :failed)
    }

    workbook = with_stubbed_pdf_parser_new(->(**kwargs) {
      PdfParserDouble.new(kwargs[:path].present? ? reader_parse : raw_parse)
    }) do
      with_stubbed_local_pdf_text_extractor_results(extractor_results) do
        process_upload(tdk_pdf_upload("synthetic readable reader text", filename: "synthetic-mismatch-loses.pdf"))
      end
    end

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal 7, workbook.row_count
    assert_equal "pdf_reader", workbook.metadata.fetch("pdf_parse_strategy")
    assert_equal "matched", workbook.metadata.fetch("pdf_reader_statement_reconciliation_status")
    assert_equal "mismatch", workbook.metadata.fetch("pdf_text_raw_statement_reconciliation_status")
    assert_equal 12, workbook.metadata.fetch("pdf_text_raw_row_count")
  end

  test "low recall readable PDF with missing layout extractor fails safely without replacing active workbook" do
    active = create_active_workbook
    low_reader_parse = parsed_pdf_statement(row_count: 2, candidate_count: 40, quality: "low_recall")
    missing_layout_result = BasTdk::LocalPdfTextExtractor::Result.new(
      success: false,
      text: nil,
      status: "missing_command",
      message: BasTdk::LocalPdfTextExtractor::MISSING_COMMAND_MESSAGE,
      attempted: false,
      error_code: :missing_command
    )
    ocr_called = false

    workbook = with_stubbed_pdf_parser_new(->(**_kwargs) { PdfParserDouble.new(low_reader_parse) }) do
      with_stubbed_local_pdf_text_extractor(missing_layout_result) do
        with_stubbed_local_ocr_new(->(**_kwargs) {
          ocr_called = true
          LocalOcrDouble.new(nil)
        }) do
          process_upload(tdk_pdf_upload("synthetic low recall reader text", filename: "synthetic-low-recall-missing-layout.pdf"))
        end
      end
    end

    assert workbook.failed?
    assert_equal 0, workbook.row_count
    assert_includes workbook.processing_errors, BasTdk::WorkbookProcessor::READABLE_PDF_UNRELIABLE_MESSAGE
    assert_equal "pdf_reader", workbook.metadata.fetch("pdf_parse_strategy")
    assert_equal "low_recall", workbook.metadata.fetch("pdf_parse_quality")
    assert_equal false, workbook.metadata.fetch("pdf_text_layout_attempted")
    assert_equal "missing_command", workbook.metadata.fetch("pdf_text_layout_status")
    assert_equal false, workbook.metadata.fetch("ocr_attempted")
    refute ocr_called
    assert_equal "processed", active.reload.status
    assert_equal active.id, bas_job.tdk_workbooks.active_processed.first.id
  end

  test "reader parse error can still use OCR when layout text is unreliable" do
    reader_error = BasTdk::PdfStatementParser::ParseError.new("Synthetic no table", code: :no_transaction_table)
    layout_parse = parsed_pdf_statement(
      row_count: 12,
      candidate_count: 12,
      quality: "poor_balance_continuity",
      balance_continuity_check_count: 12,
      balance_continuity_mismatch_count: 5,
      balance_continuity_mismatch_ratio: 0.4167
    )
    ocr_parse = parsed_pdf_statement(row_count: 8, candidate_count: 8, quality: "good")
    layout_result = BasTdk::LocalPdfTextExtractor::Result.new(
      success: true,
      text: "layout text should not be stored",
      status: "succeeded",
      message: nil,
      attempted: true,
      error_code: nil
    )
    ocr_result = BasTdk::LocalOcr::Result.new(
      success: true,
      text: "ocr text should not be stored",
      status: "succeeded",
      message: nil,
      attempted: true,
      error_code: nil
    )

    workbook = with_stubbed_pdf_parser_new(->(**kwargs) {
      result = case kwargs[:source_name]
      when /\APDF text /
        layout_parse
      when "OCR text"
        ocr_parse
      else
        reader_error
      end
      PdfParserDouble.new(result)
    }) do
      with_stubbed_local_pdf_text_extractor(layout_result) do
        with_stubbed_local_ocr(ocr_result) do
          process_upload(tdk_pdf_upload("synthetic unreadable reader text", filename: "synthetic-reader-error-layout-unreliable.pdf"))
        end
      end
    end

    assert workbook.processed?, workbook.processing_errors.to_sentence
    assert_equal 8, workbook.row_count
    assert_equal "ocr", workbook.metadata.fetch("pdf_parse_strategy")
    assert_equal "failed", workbook.metadata.fetch("pdf_reader_parse_status")
    assert_equal "poor_balance_continuity", workbook.metadata.fetch("pdf_text_layout_quality")
    assert_equal true, workbook.metadata.fetch("ocr_attempted")
    assert_equal "succeeded", workbook.metadata.fetch("ocr_status")
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

  def mapping_workbook(version_number:, mapping:, data_start_row: 1, header_row_number: nil)
    bas_job.tdk_workbooks.create!(
      status: "queued",
      source_filename: "confirmed-mapping.csv",
      version_number: version_number,
      processed_by: "tdk-processor-test",
      metadata: {
        "column_mapping_override" => {
          "header_row_number" => header_row_number,
          "data_start_row" => data_start_row,
          "columns" => mapping
        }
      }
    )
  end

  def process_existing_upload(workbook, upload)
    BasTdk::WorkbookProcessor.new(
      bas_job: bas_job,
      workbook: workbook,
      uploaded_file: upload,
      actor_username: "tdk-processor-test"
    ).call
  end

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

  def with_stubbed_local_pdf_text_extractor(result)
    with_stubbed_local_pdf_text_extractor_new(->(**_kwargs) { LocalPdfTextExtractorDouble.new(result) }) do
      yield
    end
  end

  def with_stubbed_local_pdf_text_extractor_results(results_by_mode)
    with_stubbed_local_pdf_text_extractor_new(->(**kwargs) {
      mode = kwargs.fetch(:mode)
      LocalPdfTextExtractorDouble.new(results_by_mode.fetch(mode))
    }) do
      yield
    end
  end

  def with_stubbed_local_pdf_text_extractor_new(factory)
    singleton_class = class << BasTdk::LocalPdfTextExtractor; self; end
    singleton_class.alias_method :original_tdk_local_pdf_text_extractor_new, :new
    BasTdk::LocalPdfTextExtractor.define_singleton_method(:new, &factory)
    yield
  ensure
    singleton_class.alias_method :new, :original_tdk_local_pdf_text_extractor_new
    singleton_class.remove_method :original_tdk_local_pdf_text_extractor_new
  end

  def with_stubbed_pdf_parser_new(factory)
    singleton_class = class << BasTdk::PdfStatementParser; self; end
    singleton_class.alias_method :original_tdk_pdf_statement_parser_new, :new
    BasTdk::PdfStatementParser.define_singleton_method(:new, &factory)
    yield
  ensure
    singleton_class.alias_method :new, :original_tdk_pdf_statement_parser_new
    singleton_class.remove_method :original_tdk_pdf_statement_parser_new
  end

  def parsed_pdf_statement(
    row_count:,
    candidate_count:,
    quality:,
    quality_score: nil,
    balance_continuity_check_count: row_count,
    balance_continuity_mismatch_count: 0,
    balance_continuity_mismatch_ratio: 0.0,
    balance_continuity_coverage: 1.0,
    balance_coverage: 1.0,
    amount_coverage: 1.0,
    description_coverage: 1.0,
    statement_reconciliation_status: "not_available",
    statement_reconciliation_delta_mismatch: nil,
    opening_balance_present: false,
    closing_balance_present: false,
    footer_header_contamination_count: 0
  )
    headers = [ "Date", "Category", "Amount", "GST", "Description", "Details", "Balance" ]
    rows = row_count.times.map do |index|
      {
        position: index + 1,
        source_row_number: index + 2,
        data: {
          "Date" => (Date.new(2025, 4, 1) + index).iso8601,
          "Category" => "",
          "Amount" => format("%.2f", index + 1),
          "GST" => "",
          "Description" => "Synthetic parsed row #{index + 1}",
          "Details" => "",
          "Balance" => format("%.2f", 1000 + index + 1)
        }
      }
    end

    BasTdk::PdfStatementParser::ParsedStatement.new(
      sheet_name: "PDF transaction table",
      header_row_number: 1,
      original_headers: [ "Date", "Transaction", "Debit", "Credit", "Balance" ],
      processed_headers: headers,
      rows: rows,
      metadata: {
        "row_count" => row_count,
        "candidate_transaction_count" => candidate_count,
        "quality" => quality,
        "quality_score" => quality_score || row_count * 10,
        "balance_coverage" => balance_coverage,
        "amount_coverage" => amount_coverage,
        "description_coverage" => description_coverage,
        "balance_continuity_check_count" => balance_continuity_check_count,
        "balance_continuity_mismatch_count" => balance_continuity_mismatch_count,
        "balance_continuity_coverage" => balance_continuity_coverage,
        "balance_continuity_mismatch_ratio" => balance_continuity_mismatch_ratio,
        "opening_balance_present" => opening_balance_present,
        "closing_balance_present" => closing_balance_present,
        "statement_reconciliation_status" => statement_reconciliation_status,
        "statement_reconciliation_delta_mismatch" => statement_reconciliation_delta_mismatch,
        "statement_reconciliation_amount_sum" => nil,
        "statement_reconciliation_expected_delta" => nil,
        "footer_header_contamination_count" => footer_header_contamination_count
      }
    )
  end

  def pdf_text_extraction_result(mode:, text: nil, success: true, status: nil, error_code: nil)
    status ||= success ? "succeeded" : "unsupported"
    text ||= "#{mode} synthetic text"

    BasTdk::LocalPdfTextExtractor::Result.new(
      success: success,
      text: success ? text : nil,
      status: status,
      message: nil,
      attempted: true,
      error_code: error_code,
      mode: mode,
      command: "pdftotext",
      command_resolved: nil,
      line_count: success ? text.lines.count : 0,
      byte_count: success ? text.bytesize : 0,
      text_sha256: success ? Digest::SHA256.hexdigest(text) : nil
    )
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

  def separate_debit_credit_pdf_text
    <<~TEXT
      SAMPLE BUSINESS STATEMENT
      01 DECEMBER 2024 TO 31 DECEMBER 2024
      Date     Transaction Details                         Withdrawals ($)     Deposits ($)       Balance ($)
      09 DEC   SAMPLE CREDIT TRANSACTION                            blank          265.86          1,178.79
               FROM SAMPLE PAYMENT PROCESSOR
      09 DEC   SAMPLE DEBIT TRANSACTION                              9.10           blank          1,169.69
               SAMPLE MERCHANT LOCATION
               EFFECTIVE DATE 05 DEC 2024
      09 DEC   SAMPLE PAYMENT                                       14.50           blank          1,155.19
               TO SAMPLE SOFTWARE PROVIDER
      blank    TOTALS AT END OF PAGE                              $23.60         $265.86
    TEXT
  end

  def repeated_shifted_debit_credit_pdf_text
    first_header = positioned_workbook_pdf_line(
      [ "Date", 0 ],
      [ "Transaction", 5 ],
      [ "Debit", 54 ],
      [ "Credit", 68 ],
      [ "Balance", 88 ]
    )
    second_header = positioned_workbook_pdf_line(
      [ "Date", 0 ],
      [ "Transaction", 5 ],
      [ "Debit", 24 ],
      [ "Credit", 38 ],
      [ "Balance", 58 ]
    )

    <<~TEXT
      SAMPLE BUSINESS STATEMENT
      Statement period 1 Apr 2025 - 30 Jun 2025
      #{first_header}
      #{positioned_workbook_pdf_line([ "01 Apr 2025 OPENING BALANCE", 0 ], [ "$2,000.00 CR", 88 ])}
      01 Apr SAMPLE ALPHA ROW
      #{positioned_workbook_pdf_line([ "Reference A", 7 ], [ "125.00", 76 ], [ "$2,125.00 CR", 96 ])}
      01 Apr SAMPLE BETA ROW
      #{positioned_workbook_pdf_line([ "Reference B", 7 ], [ "33.00", 54 ], [ "$", 68 ], [ "$2,092.00 CR", 88 ])}

      #{second_header}
      02 Apr SAMPLE GAMMA ROW
      #{positioned_workbook_pdf_line([ "Reference C", 7 ], [ "44.00", 24 ], [ "$", 38 ], [ "$2,048.00 CR", 58 ])}
      02 Apr SAMPLE DELTA ROW
      #{positioned_workbook_pdf_line([ "Reference D", 7 ], [ "$175.00", 44 ], [ "$2,223.00 CR", 64 ])}
      #{positioned_workbook_pdf_line([ "02 Apr EPSILON ROW", 0 ], [ "11.50", 24 ], [ "$", 38 ], [ "$2,211.50 CR", 58 ])}
      TOTALS AT END OF PERIOD
    TEXT
  end

  def positioned_workbook_pdf_line(*cells)
    cells.each_with_object(+"") do |(text, start), line|
      line << " " while line.length < start
      line << text
    end
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
