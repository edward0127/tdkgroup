require "test_helper"
require "fileutils"
require "securerandom"

class BasTdkRawCsvReaderTest < ActiveSupport::TestCase
  setup do
    @paths = []
  end

  teardown do
    @paths.each { |path| FileUtils.rm_f(path) }
  end

  test "sniffs semicolon delimiter and preserves quoted comma descriptions" do
    reader = BasTdk::RawCsvReader.new(csv_path(<<~CSV))
      Date;Amount;Description
      2025-07-01;-33.00;"Synthetic supplier, with comma"
    CSV

    sheet = reader.first_sheet

    assert_equal ";", reader.metadata.fetch("csv_delimiter")
    assert_equal 2, reader.metadata.fetch("csv_row_count")
    assert_equal "Date", sheet.cell(1, 1)
    assert_equal "-33.00", sheet.cell(2, 2)
    assert_equal "Synthetic supplier, with comma", sheet.cell(2, 3)
  end

  test "preserves real row numbers after leading blank lines" do
    reader = BasTdk::RawCsvReader.new(csv_path("\n\n2025-07-01,-33.00,Synthetic payment\n"))
    sheet = reader.first_sheet

    assert_equal 3, sheet.last_row
    assert_nil sheet.cell(1, 1)
    assert_equal "2025-07-01", sheet.cell(3, 1)
  end

  test "falls back to Windows-1252 when UTF-8 is invalid" do
    content = "Date,Amount,Description\n2025-07-01,-33.00,Synthetic Caf".b + [ 0xE9 ].pack("C") + " payment\n".b
    reader = BasTdk::RawCsvReader.new(csv_path(content))
    sheet = reader.first_sheet

    assert_equal "Windows-1252", reader.metadata.fetch("csv_encoding")
    assert_equal "Synthetic Caf\u00e9 payment", sheet.cell(2, 3)
  end

  private

  def csv_path(content)
    path = Rails.root.join("tmp", "#{SecureRandom.hex}-synthetic-reader.csv")
    File.binwrite(path, content)
    @paths << path
    path.to_s
  end
end
