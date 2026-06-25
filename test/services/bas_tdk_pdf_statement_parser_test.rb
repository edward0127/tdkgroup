require "test_helper"
require "securerandom"
require_relative "../support/synthetic_pdf_helper"

class BasTdkPdfStatementParserTest < ActiveSupport::TestCase
  include SyntheticPdfHelper

  test "parses supplied transaction text without a PDF file" do
    statement = parse_statement_text(<<~TEXT)
      Westpac Business One
      Statement period 05 December 2025 to 05 January 2026
      DATE       TRANSACTION DESCRIPTION                                      DEBIT              CREDIT             BALANCE
      08/12/25   Deposit-Osko Payment SAMPLE001 SAMPLE CUSTOMER                                   5,049.00           6,696.81
    TEXT

    assert_equal "PDF transaction table", statement.sheet_name
    assert_equal 1, statement.rows.size
    row = statement.rows.first.fetch(:data)
    assert_equal "2025-12-08", row.fetch("Date")
    assert_equal "5049.00", row.fetch("Amount")
    assert_equal "6696.81", row.fetch("Balance")
  end

  test "parse errors expose OCR eligible no text and no table reasons" do
    blank_error = assert_raises(BasTdk::PdfStatementParser::ParseError) do
      BasTdk::PdfStatementParser.new(text: "   ").call
    end

    assert_equal :no_readable_text, blank_error.code
    assert blank_error.ocr_eligible?

    no_table_error = assert_raises(BasTdk::PdfStatementParser::ParseError) do
      BasTdk::PdfStatementParser.new(text: "Statement summary only\nNo transactions here").call
    end

    assert_equal :no_transaction_table, no_table_error.code
    assert no_table_error.ocr_eligible?
  end

  test "Westpac Service Online OCR text imports deposit withdrawal and running balance rows" do
    statement = parse_statement_text(<<~TEXT)
      Westpac Service Online
      Statement period 01/05/2026 to 31/05/2026
      Date Description Withdrawals Deposits Running Balance
      Opening Balance -$69,597.25
      18/05/2026 DEPOSIT SAMPLE VIC $2,000.00 -$66,187.25
      01/05/2026 MONTHLY PLAN FEE $10.00 -$69,587.25
      31/05/2026 CLOSING BALANCE -$66,187.25
      Need help? Contact us using Westpac Online.
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 2, rows.size
    assert_equal [ "Date", "Category", "Amount", "GST", "Description", "Details", "Balance" ], statement.processed_headers

    deposit_row, withdrawal_row = rows
    assert_equal "2026-05-18", deposit_row.fetch("Date")
    assert_equal "DEPOSIT SAMPLE VIC", deposit_row.fetch("Description")
    assert_equal "2000.00", deposit_row.fetch("Amount")
    assert_equal "-66187.25", deposit_row.fetch("Balance")

    assert_equal "2026-05-01", withdrawal_row.fetch("Date")
    assert_equal "MONTHLY PLAN FEE", withdrawal_row.fetch("Description")
    assert_equal "-10.00", withdrawal_row.fetch("Amount")
    assert_equal "-69587.25", withdrawal_row.fetch("Balance")
  end

  test "Westpac Service Online OCR text joins noisy multiline descriptions conservatively" do
    statement = parse_statement_text(<<~TEXT)
      Westpac Service Online
      Statement period 01/05/2026 to 31/05/2026
      Date Description Withdrawals Deposits Running Balance
      18/05/2026 DEPOSIT
                 SAMPLE VIC
                 $2,000.00 -$66,187.25
      Visit westpac.com.au for more information.
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 1, rows.size
    assert_equal "DEPOSIT SAMPLE VIC", rows.first.fetch("Description")
    assert_equal "2000.00", rows.first.fetch("Amount")
    assert_equal "-66187.25", rows.first.fetch("Balance")
  end

  test "Westpac Service Online OCR text rejects ambiguous amount direction" do
    error = assert_raises(BasTdk::PdfStatementParser::ParseError) do
      parse_statement_text(<<~TEXT)
        Westpac Service Online
        Statement period 01/05/2026 to 31/05/2026
        Date Description Withdrawals Deposits Running Balance
        18/05/2026 CUSTOMER REFERENCE ABC $2,000.00 -$66,187.25
      TEXT
    end

    assert_equal :no_transaction_table, error.code
  end

  test "scanned OCR amount variants preserve transaction and balance signs" do
    statement = parse_statement_text(<<~TEXT)
      Bank Service Online
      Statement period 01/05/2026 to 31/05/2026
      Date Description Withdrawals Deposits Running Balance
      18/05/2026 DEPOSIT SAMPLE VIC $ 2,000.00 - $ 66,187.25
      12/05/2026 DEPOSIT SAMPLE VIC $1,500.00 -#{ocr_currency_marker} 64,687.25
      01/05/2026 MONTHLY PLAN FEE 10.00 (64,697.25)
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 3, rows.size

    assert_equal "2000.00", rows.first.fetch("Amount")
    assert_equal "-66187.25", rows.first.fetch("Balance")

    assert_equal "1500.00", rows.second.fetch("Amount")
    assert_equal "-64687.25", rows.second.fetch("Balance")

    assert_equal "-10.00", rows.third.fetch("Amount")
    assert_equal "-64697.25", rows.third.fetch("Balance")
  end

  test "scanned OCR descriptions remove orphan currency and punctuation noise" do
    statement = parse_statement_text(<<~TEXT)
      Bank Service Online
      Statement period 01/10/2025 to 31/10/2025
      Date Description Withdrawals Deposits Running Balance
      27/10/2025 DEPOSIT ONLINE SAMPLE CUSTOMER ( " / -$ #{ocr_currency_marker} 3,000.00 -$ 67,986.43
      01/10/2025 MONTHLY PLAN FEE . $ -$ $10.00 -$ 70,225.78
      01/10/2025 LINE: FEE. $ -$ $ 89.17 -$ 70,215.78
    TEXT

    descriptions = statement.rows.map { |row| row.fetch(:data).fetch("Description") }
    assert_equal [
      "DEPOSIT ONLINE SAMPLE CUSTOMER",
      "MONTHLY PLAN FEE",
      "LINE FEE"
    ], descriptions
  end

  test "scanned OCR fuzzy headers require statement context when description is omitted" do
    misspelled = parse_statement_text(<<~TEXT)
      Bank Service Online
      Transactions
      Date Deseription Withdrawals Deposits Running Balance
      18/05/2026 DEPOSIT SAMPLE VIC $ 2,000.00 -$ 66,187.25
    TEXT
    assert_equal 1, misspelled.rows.size

    omitted = parse_statement_text(<<~TEXT)
      Bank Service Online
      Transactions
      Date Withdrawals Deposits Running Balance
      18/05/2026 DEPOSIT SAMPLE VIC $ 2,000.00 -$ 66,187.25
    TEXT
    assert_equal 1, omitted.rows.size

    error = assert_raises(BasTdk::PdfStatementParser::ParseError) do
      parse_statement_text(<<~TEXT)
        Inventory export
        Date Withdrawals Deposits Running Balance
        18/05/2026 DEPOSIT SAMPLE VIC $ 2,000.00 -$ 66,187.25
      TEXT
    end
    assert_equal :no_transaction_table, error.code
  end

  test "two page scanned OCR fixture imports all rows and skips footer text" do
    fixture_text = two_page_service_online_ocr_text

    statement = parse_statement_text(fixture_text)
    rows = statement.rows.map { |row| row.fetch(:data) }

    assert_equal 16, rows.size
    assert row_for(rows, date: "2026-05-18", description: "DEPOSIT SAMPLE VIC")
    assert row_for(rows, date: "2025-09-01", description: "LINE FEE")

    deposit_row = row_for(rows, date: "2025-10-27", description: "DEPOSIT ONLINE SAMPLE CUSTOMER")
    assert_equal "3000.00", deposit_row.fetch("Amount")
    assert_equal "-67986.43", deposit_row.fetch("Balance")

    fee_row = row_for(rows, date: "2025-10-24", description: "OVERDRAWN FEE 23-OCTOBER-2025")
    assert_equal "-15.00", fee_row.fetch("Amount")
    assert_equal "-70986.43", fee_row.fetch("Balance")

    interest_row = row_for(rows, date: "2025-09-30", description: "INTEREST")
    assert_equal "-786.46", interest_row.fetch("Amount")
    assert_equal "-70126.61", interest_row.fetch("Balance")

    authority_row = rows.find { |row| row.fetch("Date") == "2025-09-23" && row.fetch("Description").start_with?("PAYMENT BY AUTHORITY TO SAMPLE FINANCE") }
    assert authority_row
    assert_equal "-745.65", authority_row.fetch("Amount")

    descriptions = rows.map { |row| row.fetch("Description") }
    descriptions.each do |description|
      refute_match(/[#{Regexp.escape(ocr_currency_marker)}$~"']/, description)
      refute_includes description, "Things you should know"
      refute_includes description, "Running balance means"
    end
  end

  test "scanned OCR inline footer text is truncated after the final transaction" do
    statement = parse_statement_text(<<~TEXT)
      Service Online Page 1 of 1
      Transactions
      Date Description Withdrawals Deposits Running Balance
      01/09/2025 LINE FEE $ 86.30 -$ 70,084.50 Things you should know
      1. Running balance means...
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 1, rows.size

    row = rows.first
    assert_equal "2025-09-01", row.fetch("Date")
    assert_equal "LINE FEE", row.fetch("Description")
    assert_equal "-86.30", row.fetch("Amount")
    assert_equal "-70084.50", row.fetch("Balance")
    refute_includes row.fetch("Description"), "Things you should know"
    refute_includes row.fetch("Description"), "Running balance means"
  end

  test "production BAS TDK services do not contain fixture only synthetic statement tokens" do
    fixture_only_tokens = [
      "SAMPLE CUSTOMER",
      "SAMPLE FINANCE",
      "SAMPLE ACCOUNT",
      "SAMPLE STATEMENT",
      "SAMPLE BANK PDF"
    ]
    production_source = Dir[Rails.root.join("app/services/bas_tdk/**/*.rb")].flat_map { |path| File.readlines(path) }.join

    fixture_only_tokens.each do |token|
      assert_not_includes production_source, token
    end
  end

  test "Westpac LT page 2 boundaries stop before closing balance fee summary and footer text" do
    statement = parse_pdf_text(<<~TEXT)
      Westpac Business One
      Statement period 05 December 2025 to 05 January 2026
      DATE       TRANSACTION DESCRIPTION                                      DEBIT              CREDIT             BALANCE
      STATEMENT OPENING BALANCE                                                                                       92,089.78
      15/12/25   Withdrawal-Osko Payment SAMPLE002 SAMPLE SUPPLIER          71,930.00                               21,769.78
      19/12/25   Withdrawal-Osko Payment SAMPLE003 SAMPLE VENDOR            17,160.00                                4,609.78
      05/01/26   CLOSING BALANCE                                                                                       4,609.78
      CONVENIENCE AT YOUR FINGERTIPS
      TRANSACTION FEE SUMMARY
      Unit Volume Price Fee
      02/01/2026 Total Electronic Credits 0.00 0.00
      Electronic Debits 0.00
      Westpac Business One
      THANK YOU FOR BANKING WITH WESTPAC
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 2, rows.size

    assert_equal "2025-12-15", rows.first.fetch("Date")
    assert_equal "-71930.00", rows.first.fetch("Amount")
    assert_equal "21769.78", rows.first.fetch("Balance")
    assert_equal "Withdrawal-Osko Payment SAMPLE002 SAMPLE SUPPLIER", rows.first.fetch("Description")

    assert_equal "2025-12-19", rows.second.fetch("Date")
    assert_equal "-17160.00", rows.second.fetch("Amount")
    assert_equal "4609.78", rows.second.fetch("Balance")
    assert_equal "Withdrawal-Osko Payment SAMPLE003 SAMPLE VENDOR", rows.second.fetch("Description")

    imported_text = rows.map { |row| row.fetch("Description") }.join(" ")
    refute_includes imported_text, "CLOSING BALANCE"
    refute_includes imported_text, "Unit Volume Price Fee"
    refute_includes imported_text, "Total Electronic Credits"
    refute_includes imported_text, "Electronic Debits"
    refute_includes imported_text, "THANK YOU FOR BANKING"
  end

  test "ANZ standalone blank tokens are removed from descriptions and still mark empty amount cells" do
    statement = parse_pdf_text(<<~TEXT)
      ANZ Business Extra
      06 MARCH 2026 TO 08 APRIL 2026
      Date       Transaction Details                                      Withdrawals ($)    Deposits ($)       Balance ($)
      06 MAR     EFTPOS blank SAMPLE PARKING\\\\                          3.47 blank 68,367.77
      07 MAR     ANZ MOBILE BANKING PAYMENT SAMPLE REF blank TO SAMPLE ACCOUNT blank 1,000.00 69,367.77
    TEXT

    withdrawal_row, deposit_row = statement.rows.map { |row| row.fetch(:data) }

    assert_equal "EFTPOS SAMPLE PARKING\\", withdrawal_row.fetch("Description")
    assert_equal "-3.47", withdrawal_row.fetch("Amount")
    assert_equal "68367.77", withdrawal_row.fetch("Balance")

    assert_equal "ANZ MOBILE BANKING PAYMENT SAMPLE REF TO SAMPLE ACCOUNT", deposit_row.fetch("Description")
    assert_equal "1000.00", deposit_row.fetch("Amount")
    assert_equal "69367.77", deposit_row.fetch("Balance")

    refute_includes withdrawal_row.fetch("Description"), "blank"
    refute_includes deposit_row.fetch("Description"), "blank"
  end

  test "ANZ final account servicing fee parses withdrawal blank deposit and balance" do
    statement = parse_pdf_text(<<~TEXT)
      ANZ Business Extra
      06 MARCH 2026 TO 08 APRIL 2026
      Date       Transaction Details                                      Withdrawals ($)    Deposits ($)       Balance ($)
      08 APR     ACCOUNT SERVICING FEE 10.00 blank 40,604.63
      blank TOTALS AT END OF PAGE
      TOTALS AT END OF PERIOD
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 1, rows.size

    row = rows.first
    assert_equal "2026-04-08", row.fetch("Date")
    assert_equal "ACCOUNT SERVICING FEE", row.fetch("Description")
    assert_equal "-10.00", row.fetch("Amount")
    assert_equal "40604.63", row.fetch("Balance")
    refute_includes row.fetch("Description"), "TOTALS AT END"
    refute_includes row.fetch("Description"), "blank"
  end

  test "ANZ totals rows are not appended and repeated headers restart table parsing" do
    statement = parse_pdf_text(<<~TEXT)
      ANZ Business Extra
      06 MARCH 2026 TO 08 APRIL 2026
      Date       Transaction Details                                      Withdrawals ($)    Deposits ($)       Balance ($)
      06 MAR     VISA DEBIT PURCHASE CARD XXXX / SAMPLE PARKING
                 / EFFECTIVE DATE 05 MAR 2026                         3.47 blank 68,367.77
      blank TOTALS AT END OF PAGE
      Date       Transaction Details                                      Withdrawals ($)    Deposits ($)       Balance ($)
      07 MAR     Transfer from savings                                    blank 1,000.00 69,367.77
      TOTALS AT END OF PERIOD
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 2, rows.size

    assert_equal "VISA DEBIT PURCHASE CARD XXXX / SAMPLE PARKING / EFFECTIVE DATE 05 MAR 2026", rows.first.fetch("Description")
    assert_equal "-3.47", rows.first.fetch("Amount")
    assert_equal "68367.77", rows.first.fetch("Balance")

    assert_equal "Transfer from savings", rows.second.fetch("Description")
    assert_equal "1000.00", rows.second.fetch("Amount")
    assert_equal "69367.77", rows.second.fetch("Balance")

    rows.each do |row|
      refute_includes row.fetch("Description"), "TOTALS AT END OF PAGE"
      refute_includes row.fetch("Description"), "TOTALS AT END OF PERIOD"
    end
  end

  private

  def ocr_currency_marker
    "\u00A7"
  end

  def row_for(rows, date:, description:)
    rows.find { |row| row.fetch("Date") == date && row.fetch("Description") == description }
  end

  def two_page_service_online_ocr_text
    <<~TEXT
      Service Online Page 1 of 2
      Transactions
      Date Description Withdrawals Deposits Running Balance
      18/05/2026 DEPOSIT SAMPLE VIC $ 2,000.00 ~ -$ 66,187.25
      12/05/2026 DEPOSIT SAMPLE VIC $ 1,400.00 ~ -$ 68,187.25
      01/05/2026 MONTHLY PLAN FEE $10.00 -$ 69,587.25
      01/05/2026 LINE FEE $ 89.17 -$ 69,577.25
      30/04/2026 INTEREST $767.41 -$ 69,488.08

      Service Online Page 2 of 2
      Date Description Withdrawals Deposits Running Balance
      31/10/2025 INTEREST $ 770.84 -$ 68,757.27
      27/10/2025 DEPOSIT ONLINE SAMPLE CUSTOMER #{ocr_currency_marker} 3,000.00 -$ 67,986.43
      24/10/2025 OVERDRAWN FEE 23-OCTOBER-2025 $ 15.00 ~ -$ 70,986.43
      23/10/2025 PAYMENT BY AUTHORITY TO SAMPLE FINANCE $745.65 -$ 70,971.43
      SAMPLE ACCOUNT REFERENCE A
      01/10/2025 MONTHLY PLAN FEE $ 10.00 -$ 70,225.78
      01/10/2025 LINE FEE $89.17 -$ 70,215.78
      30/09/2025 INTEREST $786.46 -$ 70,126.61
      23/09/2025 PAYMENT BY AUTHORITY TO SAMPLE FINANCE $ 745.65 -$ 69,340.15
      SAMPLE ACCOUNT REFERENCE B
      08/09/2025 DEPOSIT ONLINE SAMPLE CUSTOMER | $ 1,500.00 | -$ 68,594.50
      01/09/2025 MONTHLY PLAN FEE $ 10.00 -$ 70,094.50
      01/09/2025 LINE FEE $ 86.30 -$ 70,084.50
      Things you should know
      1. Running balance means...
    TEXT
  end

  def parse_statement_text(text)
    BasTdk::PdfStatementParser.new(text: text, source_name: "synthetic OCR text").call
  end

  def parse_pdf_text(text)
    path = Rails.root.join("tmp", "#{SecureRandom.hex}-tdk-parser-test.pdf")
    File.binwrite(path, synthetic_pdf(text))
    BasTdk::PdfStatementParser.new(path: path).call
  ensure
    File.delete(path) if path.present? && File.exist?(path)
  end
end
