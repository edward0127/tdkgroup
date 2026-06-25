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
      08/12/25   Deposit-Osko Payment 2234694 Ccon Group Pty Ltd                                  5,049.00           6,696.81
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
      18/05/2026 DEPOSIT CAMBERWELL VIC $2,000.00 -$66,187.25
      01/05/2026 MONTHLY PLAN FEE $10.00 -$69,587.25
      31/05/2026 CLOSING BALANCE -$66,187.25
      Need help? Contact us using Westpac Online.
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 2, rows.size
    assert_equal [ "Date", "Category", "Amount", "GST", "Description", "Details", "Balance" ], statement.processed_headers

    deposit_row, withdrawal_row = rows
    assert_equal "2026-05-18", deposit_row.fetch("Date")
    assert_equal "DEPOSIT CAMBERWELL VIC", deposit_row.fetch("Description")
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
                 CAMBERWELL VIC
                 $2,000.00 -$66,187.25
      Visit westpac.com.au for more information.
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 1, rows.size
    assert_equal "DEPOSIT CAMBERWELL VIC", rows.first.fetch("Description")
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

  test "Westpac LT page 2 boundaries stop before closing balance fee summary and footer text" do
    statement = parse_pdf_text(<<~TEXT)
      Westpac Business One
      Statement period 05 December 2025 to 05 January 2026
      DATE       TRANSACTION DESCRIPTION                                      DEBIT              CREDIT             BALANCE
      STATEMENT OPENING BALANCE                                                                                       92,089.78
      15/12/25   Withdrawal-Osko Payment 1044314 Zhienchen                  71,930.00                               21,769.78
      19/12/25   Withdrawal-Osko Payment 1097585 Okc Plaster Pty Ltd        17,160.00                                4,609.78
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
    assert_equal "Withdrawal-Osko Payment 1044314 Zhienchen", rows.first.fetch("Description")

    assert_equal "2025-12-19", rows.second.fetch("Date")
    assert_equal "-17160.00", rows.second.fetch("Amount")
    assert_equal "4609.78", rows.second.fetch("Balance")
    assert_equal "Withdrawal-Osko Payment 1097585 Okc Plaster Pty Ltd", rows.second.fetch("Description")

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
      06 MAR     EFTPOS blank EASYPARK\\\\                                3.47 blank 68,367.77
      07 MAR     ANZ MOBILE BANKING PAYMENT 197710 blank TO TDK            blank 1,000.00 69,367.77
    TEXT

    withdrawal_row, deposit_row = statement.rows.map { |row| row.fetch(:data) }

    assert_equal "EFTPOS EASYPARK\\", withdrawal_row.fetch("Description")
    assert_equal "-3.47", withdrawal_row.fetch("Amount")
    assert_equal "68367.77", withdrawal_row.fetch("Balance")

    assert_equal "ANZ MOBILE BANKING PAYMENT 197710 TO TDK", deposit_row.fetch("Description")
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
      06 MAR     VISA DEBIT PURCHASE CARD 7805 / EASYPARK PRAHRAN
                 / EFFECTIVE DATE 05 MAR 2026                         3.47 blank 68,367.77
      blank TOTALS AT END OF PAGE
      Date       Transaction Details                                      Withdrawals ($)    Deposits ($)       Balance ($)
      07 MAR     Transfer from savings                                    blank 1,000.00 69,367.77
      TOTALS AT END OF PERIOD
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 2, rows.size

    assert_equal "VISA DEBIT PURCHASE CARD 7805 / EASYPARK PRAHRAN / EFFECTIVE DATE 05 MAR 2026", rows.first.fetch("Description")
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
