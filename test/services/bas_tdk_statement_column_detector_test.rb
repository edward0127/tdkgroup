require "test_helper"

class BasTdkStatementColumnDetectorTest < ActiveSupport::TestCase
  Sheet = Struct.new(:rows) do
    def last_row
      rows.size
    end

    def last_column
      rows.map(&:size).max.to_i
    end

    def cell(row_number, column_number)
      rows.dig(row_number - 1, column_number - 1)
    end
  end

  class SparseSheet
    attr_reader :cell_calls

    def initialize(values:, last_row:, last_column:)
      @values = values
      @last_row = last_row
      @last_column = last_column
      @cell_calls = 0
    end

    attr_reader :last_row, :last_column

    def cell(row_number, column_number)
      @cell_calls += 1
      @values[[ row_number, column_number ]]
    end
  end

  test "infers reordered date description amount and reverse chronological balance" do
    result = detect([
      [ "Newest sale", "1030.00", "2025-01-05", "10.00" ],
      [ "Bank fee", "1020.00", "2025-01-04", "-5.00" ],
      [ "Customer payment", "1025.00", "2025-01-03", "20.00" ],
      [ "Supplier payment", "1005.00", "2025-01-02", "-5.00" ],
      [ "Older sale", "1010.00", "2025-01-01", "10.00" ]
    ])

    assert result.auto?, result.metadata.inspect
    assert_equal 1, result.data_start_row
    assert_nil result.header_row_number
    assert_equal "description", result.mapping.fetch("0")
    assert_equal "balance", result.mapping.fetch("1")
    assert_equal "date", result.mapping.fetch("2")
    assert_equal "amount", result.mapping.fetch("3")
  end

  test "does not mistake a repeated long account number for amount" do
    result = detect([
      [ "33005436007", "2025-01-01", "Supplier payment", "-10.00" ],
      [ "33005436007", "2025-01-02", "Customer payment", "20.00" ],
      [ "33005436007", "2025-01-03", "Bank fee", "-5.00" ],
      [ "33005436007", "2025-01-04", "Card purchase", "-7.00" ]
    ])

    assert result.auto?, result.metadata.inspect
    assert_equal "amount", result.mapping.fetch("3")
    refute_equal "amount", result.mapping.fetch("0")
    assert result.columns.first.fetch("identifier_like")
  end

  test "infers debit and credit orientation from running balance" do
    result = detect([
      [ "2025-01-01", "Opening receipt", nil, "1000.00", "1000.00" ],
      [ "2025-01-02", "Supplier payment", "10.00", nil, "990.00" ],
      [ "2025-01-03", "Customer payment", nil, "20.00", "1010.00" ],
      [ "2025-01-04", "Bank fee", "5.00", nil, "1005.00" ],
      [ "2025-01-05", "Cash receipt", nil, "30.00", "1035.00" ],
      [ "2025-01-06", "Card purchase", "12.00", nil, "1023.00" ],
      [ "2025-01-07", "Refund received", nil, "7.00", "1030.00" ]
    ])

    assert result.auto?, result.metadata.inspect
    assert_equal "date", result.mapping.fetch("0")
    assert_equal "description", result.mapping.fetch("1")
    assert_equal "debit", result.mapping.fetch("2")
    assert_equal "credit", result.mapping.fetch("3")
    assert_equal "balance", result.mapping.fetch("4")
  end

  test "requires confirmation for unsigned split columns without balance" do
    result = detect([
      [ "2025-01-01", "Opening receipt", nil, "1000.00" ],
      [ "2025-01-02", "Supplier payment", "10.00", nil ],
      [ "2025-01-03", "Customer payment", nil, "20.00" ],
      [ "2025-01-04", "Bank fee", "5.00", nil ],
      [ "2025-01-05", "Cash receipt", nil, "30.00" ]
    ])

    assert result.needs_mapping?
    assert_includes result.reason_codes, "money_columns_ambiguous"
    assert_equal 4, result.columns.size
    assert_equal 5, result.preview_rows.size
  end

  test "uses the preceding text row as a proposed header row" do
    result = detect([
      [ "When", "Memo text", "Money" ],
      [ "2025-01-01", "Supplier payment", "-10.00" ],
      [ "2025-01-02", "Customer payment", "20.00" ],
      [ "2025-01-03", "Bank fee", "-5.00" ]
    ])

    assert result.auto?, result.metadata.inspect
    assert_equal 1, result.header_row_number
    assert_equal 2, result.data_start_row
    assert_equal "When", result.columns.first.fetch("source_header")
  end

  test "rewinds to earlier valid rows whose descriptions are numeric only" do
    result = detect([
      [ "2025-01-01", "100001", "-10.00" ],
      [ "2025-01-02", "100002", "20.00" ],
      [ "2025-01-03", "Supplier payment", "-5.00" ],
      [ "2025-01-04", "Card purchase", "-7.00" ],
      [ "2025-01-05", "Refund received", "10.00" ]
    ])

    assert result.auto?, result.metadata.inspect
    assert_equal 1, result.data_start_row
    assert_equal "date", result.mapping.fetch("0")
    assert_equal "description", result.mapping.fetch("1")
    assert_equal "amount", result.mapping.fetch("2")
  end

  test "requires confirmation when bare serial dates have no bank statement evidence" do
    result = detect([
      [ "45000", "Widget A", "10" ],
      [ "45001", "Widget B", "12" ],
      [ "45002", "Widget C", "9" ],
      [ "45003", "Widget D", "14" ]
    ])

    assert result.needs_mapping?, result.metadata.inspect
    assert_includes result.reason_codes, "serial_date_without_bank_evidence"
  end

  test "allows serial dates when standard bank headers provide strong evidence" do
    result = detect([
      [ "Date", "Description", "Amount" ],
      [ "45000", "Supplier payment", "-10.00" ],
      [ "45001", "Customer payment", "20.00" ],
      [ "45002", "Bank fee", "-5.00" ],
      [ "45003", "Card purchase", "-7.00" ]
    ])

    assert result.auto?, result.metadata.inspect
    assert_equal 1, result.header_row_number
    assert_equal 2, result.data_start_row
    refute_includes result.reason_codes, "serial_date_without_bank_evidence"
  end

  test "requires confirmation when header overrides create duplicate and conflicting singleton roles" do
    result = detect([
      [ "Date", "Value Date", "Narrative", "Amount", "Debit Amount" ],
      [ "2025-01-01", "2025-01-01", "Supplier payment", "-10.00", "10.00" ],
      [ "2025-01-02", "2025-01-02", "Customer payment", "20.00", nil ],
      [ "2025-01-03", "2025-01-03", "Bank fee", "-5.00", "5.00" ],
      [ "2025-01-04", "2025-01-04", "Card purchase", "-7.00", "7.00" ]
    ])

    assert result.needs_mapping?, result.metadata.inspect
    assert_includes result.reason_codes, "invalid_auto_mapping"
    assert_equal 2, result.mapping.values.count("date")
    assert_equal 1, result.mapping.values.count("amount")
    assert_equal 1, result.mapping.values.count("debit")
  end

  test "bounds sparse worksheet scanning and only reports populated columns" do
    values = {}
    [
      [ "2025-01-01", "Supplier payment", "-10.00" ],
      [ "2025-01-02", "Customer payment", "20.00" ],
      [ "2025-01-03", "Bank fee", "-5.00" ],
      [ "2025-01-04", "Card purchase", "-7.00" ]
    ].each_with_index do |row, offset|
      values[[ offset + 1, 1 ]] = row[0]
      values[[ offset + 1, 3 ]] = row[1]
      values[[ offset + 1, 6 ]] = row[2]
    end
    sheet = SparseSheet.new(values: values, last_row: 1_000_000, last_column: 1_000_000)

    result = BasTdk::StatementColumnDetector.new(sheet: sheet).call

    assert result.auto?, result.metadata.inspect
    assert_equal BasTdk::StatementColumnDetector::MAX_ROW_SCAN_LIMIT, result.max_row
    assert_equal 6, result.max_column
    assert_equal [ 0, 2, 5 ], result.columns.map { |column| column.fetch("index") }
    assert result.preview_rows.all? { |row| row.fetch("values").size == 3 }
    assert_operator sheet.cell_calls, :<, 100_000
  end

  test "routes plausible unidentified tables to mapping and rejects non plausible tables" do
    plausible = detect([
      [ "2025-01-01", "100001", "-10.00" ],
      [ "2025-01-02", "100002", "20.00" ],
      [ "2025-01-03", "100003", "-5.00" ]
    ])
    non_plausible = detect([
      [ "Product", "Region", "Owner" ],
      [ "Widget", "East", "Alice" ],
      [ "Gadget", "West", "Bob" ]
    ])

    assert plausible.needs_mapping?, plausible.metadata.inspect
    assert_includes plausible.reason_codes, "required_columns_not_detected"
    assert_equal :reject, non_plausible.decision
    assert_includes non_plausible.reason_codes, "required_columns_not_detected"
  end

  private

  def detect(rows)
    BasTdk::StatementColumnDetector.new(sheet: Sheet.new(rows)).call
  end
end
