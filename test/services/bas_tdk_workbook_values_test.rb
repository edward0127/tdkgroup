require "test_helper"

class BasTdkWorkbookValuesTest < ActiveSupport::TestCase
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
