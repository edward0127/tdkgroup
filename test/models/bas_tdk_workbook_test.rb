require "test_helper"

class BasTdkWorkbookTest < ActiveSupport::TestCase
  test "needs mapping is a valid terminal processing state" do
    workbook = BasTdkWorkbook.new(status: "needs_mapping")

    assert workbook.needs_mapping?
    assert workbook.terminal_status?
    assert_includes BasTdkWorkbook::STATUS_VALUES, "needs_mapping"
  end
end
