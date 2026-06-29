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
    statement = parse_layout_text(<<~TEXT)
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

  test "scanned OCR deposit osko descriptions prefer deposit direction" do
    statement = parse_layout_text(<<~TEXT)
      Bank Service Online
      Statement period 01/02/2026 to 28/02/2026
      Date Description Withdrawals Deposits Running Balance
      16/02/2026 DEPOSIT-OSKO PAYMENT SAMPLE CUSTOMER $ 1,300.00 -$ 70,905.80
      16/02/2026 DEPOSIT OSKO PAYMENT SAMPLE CUSTOMER $ 1,300.00 -$ 70,905.80
      16/02/2026 OSKO DEPOSIT SAMPLE CUSTOMER $ 1,300.00 -$ 70,905.80
      16/02/2026 WITHDRAWAL-OSKO PAYMENT SAMPLE SUPPLIER $ 1,300.00 -$ 70,905.80
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 4, rows.size

    assert_equal "1300.00", rows.first.fetch("Amount")
    assert_equal "1300.00", rows.second.fetch("Amount")
    assert_equal "1300.00", rows.third.fetch("Amount")
    assert_equal "-1300.00", rows.fourth.fetch("Amount")

    assert_equal "-70905.80", rows.first.fetch("Balance")
    assert_equal "-70905.80", rows.second.fetch("Balance")
    assert_equal "-70905.80", rows.third.fetch("Balance")
    assert_equal "-70905.80", rows.fourth.fetch("Balance")
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

  test "scanned OCR over precise decimal amounts are truncated to cents" do
    statement = parse_statement_text(<<~TEXT)
      Bank Service Online
      Statement period 01/09/2025 to 30/11/2025
      Date Description Withdrawals Deposits Running Balance
      03/11/2025 LINE FEE $ 86.307 -$ 68,843.57
      01/10/2025 MONTHLY PLAN FEE $ 10.000 -$ 70,225.78
      23/09/2025 PAYMENT BY AUTHORITY TO SAMPLE FINANCE $ 745.650 -$ 69,340.15
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 3, rows.size

    assert_equal "-86.30", rows.first.fetch("Amount")
    assert_equal "-68843.57", rows.first.fetch("Balance")

    assert_equal "-10.00", rows.second.fetch("Amount")
    assert_equal "-70225.78", rows.second.fetch("Balance")

    assert_equal "-745.65", rows.third.fetch("Amount")
    assert_equal "-69340.15", rows.third.fetch("Balance")
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

  test "scanned OCR descriptions truncate trailing footer URLs" do
    https_statement = parse_statement_text(<<~TEXT)
      Bank Service Online
      Statement period 01/05/2026 to 31/05/2026
      Date Description Withdrawals Deposits Running Balance
      01/05/2026 LINE FEE $ 10.00 -$ 70,000.00 https://example.internal/path 25/05/2026
    TEXT

    https_row = https_statement.rows.first.fetch(:data)
    assert_equal "LINE FEE", https_row.fetch("Description")
    assert_equal "-10.00", https_row.fetch("Amount")

    www_statement = parse_statement_text(<<~TEXT)
      Bank Service Online
      Statement period 01/05/2026 to 31/05/2026
      Date Description Withdrawals Deposits Running Balance
      01/05/2026 MONTHLY PLAN FEE $ 10.00 -$ 70,000.00 www.example.com/footer
    TEXT

    www_row = www_statement.rows.first.fetch(:data)
    assert_equal "MONTHLY PLAN FEE", www_row.fetch("Description")
    assert_equal "-10.00", www_row.fetch("Amount")

    service_online_statement = parse_statement_text(<<~TEXT)
      Bank Service Online
      Statement period 01/05/2026 to 31/05/2026
      Date Description Withdrawals Deposits Running Balance
      01/05/2026 LINE FEE $ 10.00 -$ 70,000.00 service online page 2 of 2
    TEXT

    service_online_row = service_online_statement.rows.first.fetch(:data)
    assert_equal "LINE FEE", service_online_row.fetch("Description")
    assert_equal "-10.00", service_online_row.fetch("Amount")
  end

  test "scanned OCR descriptions remove trailing artefacts without stripping references" do
    statement = parse_statement_text(<<~TEXT)
      Bank Service Online
      Statement period 01/05/2026 to 31/05/2026
      Date Description Withdrawals Deposits Running Balance
      18/05/2026 DEPOSIT SAMPLE VIC1 $ 2,000.00 -$ 66,187.25
      19/05/2026 DEPOSIT SAMPLE LOCATION s $ 3.00 -$ 66,184.25
      20/05/2026 LINE FEE _ $ 10.00 -$ 66,194.25
      21/05/2026 MONTHLY PLAN FEE . $ 10.00 -$ 66,204.25
      22/05/2026 TRANSFER DEPOSIT 0000000 AT LOCATION VI [ c $ 25.00 -$ 66,179.25
      23/05/2026 TRANSFER DEPOSIT 0000000 AT LOCATION VI [ #{e_acute} pcos) $ 30.00 -$ 66,149.25
      24/05/2026 TRANSFER DEPOSIT SAMPLE AT LOCATION NS [ w $ 35.00 -$ 66,114.25
      25/05/2026 TRANSFER DEPOSIT SAMPLE AT LOCATION QL [ d $ 40.00 -$ 66,074.25
      26/05/2026 DEPOSIT SAMPLE LOCATION #{e_acute} $ 45.00 -$ 66,029.25
      27/05/2026 LINE FEE - $ 10.00 -$ 66,039.25
      28/05/2026 DEPOSIT SAMPLE CUSTOMER } $ 50.00 -$ 65,989.25
      29/05/2026 TRANSFER DEPOSIT SAMPLE REF A $ 55.00 -$ 65,934.25
      30/05/2026 DEPOSIT PAYMENT REF ABC123 $ 60.00 -$ 65,874.25
      31/05/2026 DEPOSIT PAYMENT REF 12345 $ 65.00 -$ 65,809.25
    TEXT

    descriptions = statement.rows.map { |row| row.fetch(:data).fetch("Description") }
    assert_equal [
      "DEPOSIT SAMPLE VIC",
      "DEPOSIT SAMPLE LOCATION",
      "LINE FEE",
      "MONTHLY PLAN FEE",
      "TRANSFER DEPOSIT 0000000 AT LOCATION VIC",
      "TRANSFER DEPOSIT 0000000 AT LOCATION VIC",
      "TRANSFER DEPOSIT SAMPLE AT LOCATION NSW",
      "TRANSFER DEPOSIT SAMPLE AT LOCATION QLD",
      "DEPOSIT SAMPLE LOCATION",
      "LINE FEE",
      "DEPOSIT SAMPLE CUSTOMER",
      "TRANSFER DEPOSIT SAMPLE REF A",
      "DEPOSIT PAYMENT REF ABC123",
      "DEPOSIT PAYMENT REF 12345"
    ], descriptions
  end

  test "scanned OCR date starting lines without amounts continue the active description" do
    statement = parse_statement_text(<<~TEXT)
      Bank Service Online
      Statement period 01/02/2026 to 28/02/2026
      Date Description Withdrawals Deposits Running Balance
      16/02/2026 DEPOSIT-OSKO PAYMENT SAMPLE CUSTOMER 1 $ 1,300.00 -$ 70,905.80
      5 FEB 2026
      17/02/2026 DEPOSIT-OSKO PAYMENT SAMPLE CUSTOMER $ 100.00 -$ 70,805.80
      5 FEB 2026
      5 FEB 2026 LINE FEE $ 10.00 -$ 70,815.80
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 3, rows.size
    assert_equal "DEPOSIT-OSKO PAYMENT SAMPLE CUSTOMER 15 FEB 2026", rows.first.fetch("Description")
    assert_equal "1300.00", rows.first.fetch("Amount")
    assert_equal "DEPOSIT-OSKO PAYMENT SAMPLE CUSTOMER 5 FEB 2026", rows.second.fetch("Description")
    assert_equal "100.00", rows.second.fetch("Amount")
    assert_equal "2026-02-05", rows.third.fetch("Date")
    assert_equal "LINE FEE", rows.third.fetch("Description")
    assert_equal "-10.00", rows.third.fetch("Amount")
  end

  test "scanned OCR footer metadata is not appended to the final transaction" do
    statement = parse_statement_text(<<~TEXT)
      Service Online Page 1 of 1
      Transactions
      Date Description Withdrawals Deposits Running Balance
      01/09/2025 LINE FEE $ 86.30 -$ 70,084.50 Printed: 25/05/2026
      gsso intranet service online
      page 1 of 1
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 1, rows.size

    row = rows.first
    assert_equal "LINE FEE", row.fetch("Description")
    refute_includes row.fetch("Description"), "Printed"
    refute_includes row.fetch("Description"), "gsso"
    refute_includes row.fetch("Description"), "service online"
    refute_includes row.fetch("Description"), "page 1 of"
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

  test "scanned OCR fixture imports deposit osko and decimal noise rows and skips footer" do
    statement = parse_statement_text(<<~TEXT)
      Service Online Page 1 of 2
      Transactions
      Date Description Withdrawals Deposits Running Balance
      16/02/2026 DEPOSIT-OSKO PAYMENT SAMPLE CUSTOMER $ 1,300.00 -$ 70,905.80
      03/11/2025 LINE FEE $ 86.307 -$ 68,843.57
      Things you should know
      1. Running balance means...
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 2, rows.size

    deposit_row = rows.first
    assert_equal "2026-02-16", deposit_row.fetch("Date")
    assert_equal "DEPOSIT-OSKO PAYMENT SAMPLE CUSTOMER", deposit_row.fetch("Description")
    assert_equal "1300.00", deposit_row.fetch("Amount")
    assert_equal "-70905.80", deposit_row.fetch("Balance")

    fee_row = rows.second
    assert_equal "2025-11-03", fee_row.fetch("Date")
    assert_equal "LINE FEE", fee_row.fetch("Description")
    assert_equal "-86.30", fee_row.fetch("Amount")
    assert_equal "-68843.57", fee_row.fetch("Balance")

    descriptions = rows.map { |row| row.fetch("Description") }
    descriptions.each do |description|
      refute_match(/[$#{Regexp.escape(ocr_currency_marker)}]/, description)
      refute_includes description, "Things you should know"
      refute_includes description, "Running balance means"
    end
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

  test "metadata reports poor balance continuity when parsed rows skip running balances" do
    statement = parse_layout_text(<<~TEXT)
      SAMPLE BUSINESS STATEMENT
      Statement period 1 Apr 2025 - 30 Jun 2025
      Date Transaction Debit Credit Balance
      01 Apr 2025 OPENING BALANCE $1,000.00 CR
      01 Apr SAMPLE FIRST ROW 10.00 $ $990.00 CR
      02 Apr SAMPLE GAP ROW 5.00 $ $970.00 CR
      03 Apr SAMPLE CREDIT ROW $20.00 $990.00 CR
      04 Apr SAMPLE DEBIT ROW 10.00 $ $980.00 CR
      05 Apr SAMPLE SECOND GAP ROW 5.00 $ $960.00 CR
      06 Apr SAMPLE CREDIT TWO $10.00 $970.00 CR
      07 Apr SAMPLE THIRD GAP ROW 8.00 $ $950.00 CR
      08 Apr SAMPLE CREDIT THREE $25.00 $975.00 CR
      09 Apr SAMPLE FOURTH GAP ROW 5.00 $ $960.00 CR
      10 Apr SAMPLE CREDIT FOUR $10.00 $970.00 CR
      11 Apr SAMPLE DEBIT TWO 20.00 $ $950.00 CR
      12 Apr SAMPLE CREDIT FIVE $5.00 $955.00 CR
    TEXT

    metadata = statement.metadata
    assert_equal 12, statement.rows.size
    assert_operator metadata.fetch("balance_continuity_check_count"), :>=, 10
    assert_operator metadata.fetch("balance_continuity_mismatch_count"), :>=, 3
    assert_operator metadata.fetch("balance_continuity_mismatch_ratio"), :>, 0.05
    assert_equal "poor_balance_continuity", metadata.fetch("quality")
  end

  test "metadata reports good balance continuity for complete debit credit balance rows" do
    statement = parse_layout_text(<<~TEXT)
      SAMPLE BUSINESS STATEMENT
      Statement period 1 Apr 2025 - 30 Jun 2025
      Date Transaction Debit Credit Balance
      01 Apr 2025 OPENING BALANCE $1,000.00 CR
      01 Apr SAMPLE DEBIT 10.00 $ $990.00 CR
      02 Apr SAMPLE CREDIT $15.00 $1,005.00 CR
      03 Apr SAMPLE DEBIT TWO 5.00 $ $1,000.00 CR
    TEXT

    metadata = statement.metadata
    assert_equal 3, statement.rows.size
    assert_equal 3, metadata.fetch("balance_continuity_check_count")
    assert_equal 0, metadata.fetch("balance_continuity_mismatch_count")
    assert_equal 0.0, metadata.fetch("balance_continuity_mismatch_ratio")
    assert_equal 1.0, metadata.fetch("balance_continuity_coverage")
    assert_equal "good", metadata.fetch("quality")
  end

  test "statement reconciliation matches opening plus row amounts to closing balance" do
    statement = parse_layout_text(<<~TEXT)
      SAMPLE BUSINESS STATEMENT
      Statement period 1 Apr 2025 - 30 Jun 2025
      Date Transaction Debit Credit Balance
      01 Apr 2025 OPENING BALANCE $1,000.00 CR
      01 Apr SAMPLE DEBIT 10.00 $ $990.00 CR
      02 Apr SAMPLE CREDIT $15.00 $1,005.00 CR
      03 Apr SAMPLE DEBIT TWO 5.00 $ $1,000.00 CR
      03 Apr 2025 CLOSING BALANCE $1,000.00 CR
    TEXT

    metadata = statement.metadata
    assert_equal 3, statement.rows.size
    assert_equal 0, metadata.fetch("balance_continuity_mismatch_count")
    assert_equal true, metadata.fetch("opening_balance_present")
    assert_equal true, metadata.fetch("closing_balance_present")
    assert_equal "matched", metadata.fetch("statement_reconciliation_status")
    assert_equal "0.00", metadata.fetch("statement_reconciliation_delta_mismatch")
    assert_equal "good", metadata.fetch("quality")
  end

  test "statement reconciliation detects missing rows even if parser returns some rows" do
    statement = parse_layout_text(<<~TEXT)
      SAMPLE BUSINESS STATEMENT
      Statement period 1 Apr 2025 - 30 Jun 2025
      Date Transaction Debit Credit Balance
      01 Apr 2025 OPENING BALANCE $1,000.00 CR
      01 Apr SAMPLE DEBIT 10.00 $ $990.00 CR
      02 Apr SAMPLE CREDIT $15.00 $1,005.00 CR
      03 Apr SAMPLE DEBIT TWO 5.00 $ $1,000.00 CR
      03 Apr 2025 CLOSING BALANCE $980.00 CR
    TEXT

    metadata = statement.metadata
    assert_equal 3, statement.rows.size
    assert_equal "mismatch", metadata.fetch("statement_reconciliation_status")
    refute_equal "good", metadata.fetch("quality")
    assert_equal "20.00", metadata.fetch("statement_reconciliation_delta_mismatch")
  end

  test "candidate count handles multiline amount rows" do
    statement = parse_layout_text(<<~TEXT)
      SAMPLE BUSINESS STATEMENT
      Statement period 1 Apr 2025 - 30 Jun 2025
      Date Transaction Debit Credit Balance
      01 Apr 2025 OPENING BALANCE $1,000.00 CR
      01 Apr SAMPLE FIRST
             DETAIL LINE
             REFERENCE LINE
             10.00 $ $990.00 CR
      02 Apr SAMPLE SECOND
             DETAIL LINE
             REFERENCE LINE
             $15.00 $1,005.00 CR
      03 Apr SAMPLE THIRD
             DETAIL LINE
             REFERENCE LINE
             5.00 $ $1,000.00 CR
    TEXT

    metadata = statement.metadata
    assert_equal 3, statement.rows.size
    assert_operator metadata.fetch("candidate_transaction_count"), :>=, statement.rows.size
    assert_operator metadata.fetch("candidate_transaction_count"), :<=, statement.rows.size + 1
    refute_equal "low_recall", metadata.fetch("quality")
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

  test "separate withdrawal and deposit columns import withdrawals as negative with continuation lines" do
    statement = parse_pdf_text(<<~TEXT)
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

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 3, rows.size

    assert_equal "265.86", rows.first.fetch("Amount")
    assert_equal "1178.79", rows.first.fetch("Balance")
    assert_equal "-9.10", rows.second.fetch("Amount")
    assert_equal "1169.69", rows.second.fetch("Balance")
    assert_equal "-14.50", rows.third.fetch("Amount")
    assert_equal "1155.19", rows.third.fetch("Balance")

    imported_text = rows.map { |row| row.fetch("Description") }.join(" ")
    refute_includes imported_text, "blank"
    refute_includes imported_text, "TOTALS AT END OF PAGE"
  end

  test "separate debit credit column spans classify right aligned debit amounts before nearest-header fallback" do
    header = "Date     Transaction Details          Withdrawals ($) Deposits ($) Balance ($)"
    credit_start = header.index("Deposits")
    balance_start = header.index("Balance")
    amount = "123.45"
    balance = "1,055.34"
    description = "09 DEC   SAMPLE COLUMN POSITION DEBIT"
    debit_line = description.ljust(credit_start - amount.length) + amount
    debit_line = debit_line.ljust(balance_start) + balance

    statement = parse_statement_text(<<~TEXT)
      SAMPLE BUSINESS STATEMENT
      01 DECEMBER 2024 TO 31 DECEMBER 2024
      #{header}
      #{debit_line}
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 1, rows.size
    assert_equal "-123.45", rows.first.fetch("Amount")
    assert_equal "1055.34", rows.first.fetch("Balance")
  end

  test "uses the current repeated header column positions when debit credit table shifts" do
    first_header = positioned_pdf_line(
      [ "Date", 0 ],
      [ "Transaction", 5 ],
      [ "Debit", 54 ],
      [ "Credit", 68 ],
      [ "Balance", 88 ]
    )
    second_header = positioned_pdf_line(
      [ "Date", 0 ],
      [ "Transaction", 5 ],
      [ "Debit", 24 ],
      [ "Credit", 38 ],
      [ "Balance", 58 ]
    )

    statement = parse_pdf_text(<<~TEXT)
      SAMPLE BUSINESS STATEMENT
      Statement period 1 Apr 2025 - 30 Jun 2025
      #{first_header}
      #{positioned_pdf_line([ "01 Apr 2025 OPENING BALANCE", 0 ], [ "$2,000.00 CR", 88 ])}
      01 Apr SAMPLE ALPHA ROW
      #{positioned_pdf_line([ "Reference A", 7 ], [ "125.00", 76 ], [ "$2,125.00 CR", 96 ])}
      01 Apr SAMPLE BETA ROW
      #{positioned_pdf_line([ "Reference B", 7 ], [ "33.00", 54 ], [ "$", 68 ], [ "$2,092.00 CR", 88 ])}

      #{second_header}
      02 Apr SAMPLE GAMMA ROW
      #{positioned_pdf_line([ "Reference C", 7 ], [ "44.00", 24 ], [ "$", 38 ], [ "$2,048.00 CR", 58 ])}
      02 Apr SAMPLE DELTA ROW
      #{positioned_pdf_line([ "Reference D", 7 ], [ "$175.00", 44 ], [ "$2,223.00 CR", 64 ])}
      #{positioned_pdf_line([ "02 Apr EPSILON ROW", 0 ], [ "11.50", 24 ], [ "$", 38 ], [ "$2,211.50 CR", 58 ])}
      TOTALS AT END OF PERIOD
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 5, rows.size

    assert_equal [ "125.00", "-33.00", "-44.00", "175.00", "-11.50" ], rows.map { |row| row.fetch("Amount") }
    assert_equal [ "2125.00", "2092.00", "2048.00", "2223.00", "2211.50" ], rows.map { |row| row.fetch("Balance") }
    assert_equal "SAMPLE ALPHA ROW Reference A", rows.first.fetch("Description")
    assert_equal "EPSILON ROW", rows.last.fetch("Description")

    imported_text = rows.map { |row| row.fetch("Description") }.join(" ")
    refute_includes imported_text, "OPENING BALANCE"
    refute_includes imported_text, "$"
    refute_match(/\bblank\b/i, imported_text)
    refute_match(/\b(?:CR|DR)\z/i, imported_text)
  end

  test "multiline amount rows are classified by debit credit columns without description keywords" do
    header = positioned_pdf_line(
      [ "Date", 0 ],
      [ "Description", 8 ],
      [ "Debit", 42 ],
      [ "Credit", 56 ],
      [ "Balance", 76 ]
    )

    statement = parse_pdf_text(<<~TEXT)
      SAMPLE BUSINESS STATEMENT
      Statement period 1 Apr 2025 - 30 Jun 2025
      #{header}
      03 Apr ALPHA NEUTRAL
      #{positioned_pdf_line([ "Reference A", 9 ], [ "12.00", 42 ], [ "$", 56 ], [ "$1,988.00 CR", 76 ])}
      03 Apr BRAVO NEUTRAL
      #{positioned_pdf_line([ "Reference B", 9 ], [ "34.00", 62 ], [ "$2,022.00 CR", 82 ])}
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 2, rows.size
    assert_equal [ "-12.00", "34.00" ], rows.map { |row| row.fetch("Amount") }
    assert_equal [ "1988.00", "2022.00" ], rows.map { |row| row.fetch("Balance") }
    assert_equal "ALPHA NEUTRAL Reference A", rows.first.fetch("Description")
    assert_equal "BRAVO NEUTRAL Reference B", rows.second.fetch("Description")
  end

  test "single header debit credit layout still parses with fallback header shape" do
    header = positioned_pdf_line(
      [ "Date", 0 ],
      [ "Transaction", 8 ],
      [ "Debit", 48 ],
      [ "Credit", 62 ],
      [ "Balance", 82 ]
    )

    statement = parse_pdf_text(<<~TEXT)
      SAMPLE BUSINESS STATEMENT
      Statement period 1 Apr 2025 - 30 Jun 2025
      #{header}
      #{positioned_pdf_line([ "04 Apr SAMPLE ONE", 0 ], [ "21.00", 48 ], [ "$", 62 ], [ "$1,979.00 CR", 82 ])}
      #{positioned_pdf_line([ "04 Apr SAMPLE TWO", 0 ], [ "55.00", 62 ], [ "$2,034.00 CR", 82 ])}
      04 Apr SAMPLE THREE
      #{positioned_pdf_line([ "Reference C", 8 ], [ "7.50", 48 ], [ "$", 62 ], [ "$2,026.50 CR", 82 ])}
      TOTALS AT END OF PAGE
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 3, rows.size
    assert_equal [ "-21.00", "55.00", "-7.50" ], rows.map { |row| row.fetch("Amount") }
    assert_equal [ "1979.00", "2034.00", "2026.50" ], rows.map { |row| row.fetch("Balance") }
    assert_equal "SAMPLE THREE Reference C", rows.third.fetch("Description")
    refute_includes rows.map { |row| row.fetch("Description") }.join(" "), "TOTALS AT END"
  end

  test "split readable debit credit balance header imports multiline rows and skips technical page lines" do
    statement = parse_layout_text(<<~TEXT)
      SAMPLE BUSINESS STATEMENT
      Statement period 1 Apr 2025 - 30 Jun 2025
      Date Transaction
      Debit
      Credit
      Balance
      01 Apr 2025 OPENING BALANCE $770,419.32 CR
      01 Apr CARD PURCHASE SAMPLE
      Card xx0000
      Value Date: 30/03/2025 33.00 $ $770,386.32 CR
      01 Apr TRANSFER TO SAMPLE SUPPLIER
      NetBank REF 3,411.72 $ $766,974.60 CR
      01 Apr FAST TRANSFER FROM SAMPLE CUSTOMER
      Repair $350.00 $767,324.60 CR
      01 Apr POS 123456 01 APR $1,321.00 $768,645.60 CR
      Statement 44 (Page 2 of 2)
      Account Number 00000000
      17013.40872.1.9 ZZ258R3 V06.00.37
      *#*
      02 Apr DIRECT CREDIT SAMPLE CUSTOMER $7,410.00 $776,055.60 CR
      02 Apr CARD PURCHASE SAMPLE
      Value Date: 01/04/2025 55.60 $ $776,000.00 CR
      02 Apr 2025 CLOSING BALANCE $776,000.00 CR
      Transaction Summary
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 6, rows.size
    assert_equal [ "-33.00", "-3411.72", "350.00", "1321.00", "7410.00", "-55.60" ], rows.map { |row| row.fetch("Amount") }
    assert_equal [ "770386.32", "766974.60", "767324.60", "768645.60", "776055.60", "776000.00" ], rows.map { |row| row.fetch("Balance") }

    assert_equal "CARD PURCHASE SAMPLE Card xx0000 Value Date: 30/03/2025", rows.first.fetch("Description")
    assert_equal "TRANSFER TO SAMPLE SUPPLIER NetBank REF", rows.second.fetch("Description")
    assert_equal "FAST TRANSFER FROM SAMPLE CUSTOMER Repair", rows.third.fetch("Description")

    imported_text = rows.map { |row| row.fetch("Description") }.join(" ")
    refute_includes imported_text, "$"
    refute_match(/\bCR\b/, imported_text)
    refute_match(/\bDR\b/, imported_text)
    refute_includes imported_text, "Statement 44"
    refute_includes imported_text, "Account Number"
    refute_includes imported_text, "ZZ258R3"
    refute_includes imported_text, "V06.00.37"
    refute_includes imported_text, "OPENING BALANCE"
    refute_includes imported_text, "CLOSING BALANCE"
    refute_includes imported_text, "Transaction Summary"
  end

  test "glued credit and debit balance suffixes set balance sign" do
    statement = parse_layout_text(<<~TEXT)
      SAMPLE BUSINESS STATEMENT
      Statement period 1 Apr 2025 - 30 Jun 2025
      Date Transaction
      Debit
      Credit
      Balance
      01 Apr 2025 OPENING BALANCE $1,000.00 CR
      01 Apr SAMPLE CREDIT ROW $50.00 $1,050.00CR
      02 Apr SAMPLE DEBIT ROW 25.00 $ $1,025.00 CR
      03 Apr SAMPLE OVERDRAWN ROW 2,259.56 $ $1,234.56DR
    TEXT

    rows = statement.rows.map { |row| row.fetch(:data) }
    assert_equal 3, rows.size
    assert_equal [ "1050.00", "1025.00", "-1234.56" ], rows.map { |row| row.fetch("Balance") }
    assert_equal [ "50.00", "-25.00", "-2259.56" ], rows.map { |row| row.fetch("Amount") }

    descriptions = rows.map { |row| row.fetch("Description") }.join(" ")
    refute_match(/\b(?:CR|DR)\b/, descriptions)
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

  def e_acute
    "\u00E9"
  end

  def row_for(rows, date:, description:)
    rows.find { |row| row.fetch("Date") == date && row.fetch("Description") == description }
  end

  def positioned_pdf_line(*cells)
    cells.each_with_object(+"") do |(text, start), line|
      line << " " while line.length < start
      line << text
    end
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

  def parse_layout_text(text)
    BasTdk::PdfStatementParser.new(text: text, source_name: "synthetic layout text").call
  end

  def parse_pdf_text(text)
    path = Rails.root.join("tmp", "#{SecureRandom.hex}-tdk-parser-test.pdf")
    File.binwrite(path, synthetic_pdf(text))
    BasTdk::PdfStatementParser.new(path: path).call
  ensure
    File.delete(path) if path.present? && File.exist?(path)
  end
end
