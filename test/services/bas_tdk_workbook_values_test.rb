require "test_helper"

class BasTdkWorkbookValuesTest < ActiveSupport::TestCase
  test "parses month name bank statement dates" do
    assert_equal Date.new(2026, 6, 23), BasTdk::WorkbookValues.parse_date("23 Jun 26")
    assert_equal Date.new(2026, 6, 23), BasTdk::WorkbookValues.parse_date("23 Jun 2026")
    assert_equal Date.new(2026, 6, 1), BasTdk::WorkbookValues.parse_date("1 Jun 26")
    assert_equal Date.new(2026, 6, 1), BasTdk::WorkbookValues.parse_date("01-Jun-26")
    assert_equal Date.new(2026, 6, 1), BasTdk::WorkbookValues.parse_date("01-Jun-2026")
    assert_equal Date.new(2026, 6, 1), BasTdk::WorkbookValues.parse_date("1 June 2026")
    assert_equal Date.new(2026, 6, 1), BasTdk::WorkbookValues.parse_date("1 June 26")
  end

  test "keeps existing date parsing formats" do
    assert_equal Date.new(2026, 6, 23), BasTdk::WorkbookValues.parse_date("2026-06-23")
    assert_equal Date.new(2026, 6, 23), BasTdk::WorkbookValues.parse_date("23/06/2026")
    assert_equal Date.new(2025, 12, 31), BasTdk::WorkbookValues.parse_date("46022")
  end

  test "parses common numeric bank statement dates" do
    assert_equal Date.new(2025, 1, 5), BasTdk::WorkbookValues.parse_date("05/01/25")
    assert_equal Date.new(2025, 1, 5), BasTdk::WorkbookValues.parse_date("2025/01/05")
    assert_equal Date.new(2025, 1, 5), BasTdk::WorkbookValues.parse_date("5/1/25 09:30 AM")
    assert_nil BasTdk::WorkbookValues.parse_date("12/31/25")
  end

  test "parses debit credit and trailing-minus accounting amounts" do
    assert_equal BigDecimal("123.45"), BasTdk::WorkbookValues.parse_amount("123.45 CR")
    assert_equal BigDecimal("123.45"), BasTdk::WorkbookValues.parse_amount("$123.45cr")
    assert_equal BigDecimal("-123.45"), BasTdk::WorkbookValues.parse_amount("123.45 DR")
    assert_equal BigDecimal("-123.45"), BasTdk::WorkbookValues.parse_amount("123.45-")
  end

  test "cleans only clear Excel decimal noise" do
    assert_equal "8770.72", BasTdk::WorkbookValues.clean_excel_decimal_noise("8770.7199999999993")
    assert_equal "70089.57", BasTdk::WorkbookValues.clean_excel_decimal_noise("70089.570000000007")
    assert_equal "118623.07", BasTdk::WorkbookValues.clean_excel_decimal_noise("118623.07")
    assert_equal "7341056315", BasTdk::WorkbookValues.clean_excel_decimal_noise("7341056315")
    assert_equal "123.456789", BasTdk::WorkbookValues.clean_excel_decimal_noise("123.456789")
    assert_equal "ABC123", BasTdk::WorkbookValues.clean_excel_decimal_noise("ABC123")
    assert_equal " ABC123 ", BasTdk::WorkbookValues.clean_excel_decimal_noise(" ABC123 ")
  end
end
