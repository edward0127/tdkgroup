require "test_helper"
require "securerandom"
require_relative "../support/synthetic_pdf_helper"

class BasTdkPdfStatementParserTest < ActiveSupport::TestCase
  include SyntheticPdfHelper

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

  def parse_pdf_text(text)
    path = Rails.root.join("tmp", "#{SecureRandom.hex}-tdk-parser-test.pdf")
    File.binwrite(path, synthetic_pdf(text))
    BasTdk::PdfStatementParser.new(path: path).call
  ensure
    File.delete(path) if path.present? && File.exist?(path)
  end
end
