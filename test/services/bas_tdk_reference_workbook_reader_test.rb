require "test_helper"
require_relative "../support/tdk_workbook_helper"

class BasTdkReferenceWorkbookReaderTest < ActiveSupport::TestCase
  test "retains uncoded transaction rows for category coverage calculations" do
    upload = tdk_csv_upload(<<~CSV, filename: "category-coverage.csv")
      Description,Category,Amount,GST
      Fast Transfer From ALICE,Sales,40.00,
      Fast Transfer From BOB,,50.00,
      Footer total,,90.00,
    CSV
    result = reader_for(upload).call

    assert result.success?, result.errors.to_sentence
    assert_equal 2, result.rows.length
    assert_equal "Sales", result.rows.first.category
    assert_equal "", result.rows.second.category
  end

  include TdkWorkbookHelper

  test "reads a real prior-quarter debit credit header shape with signed GST ratios" do
    upload = tdk_xlsx_upload([
      [ "Bank Account", "Date", "Narrative", "Debit Amount", "Credit Amount", "Balance", "Category", "GST" ],
      [ "33005436007", "30/03/2026", "OFFICEWORKS", 121.00, nil, 771.50, "Office expenses", -11.00 ],
      [ "33005436007", "29/03/2026", "DEPOSIT OSKO CLIENT", nil, 3_000.00, 3_771.50, "Sales", 0 ]
    ], filename: "prior-quarter.xlsx")

    result = reader_for(upload).call

    assert result.success?, result.errors.to_sentence
    assert_equal({
      "description" => 3,
      "category" => 7,
      "debit" => 4,
      "credit" => 5,
      "gst" => 8
    }, result.column_mapping)
    assert_equal 2, result.rows.length
    debit, credit = result.rows
    assert_equal BigDecimal("-121"), debit.amount
    assert_equal BigDecimal("-11"), debit.gst_amount
    assert_equal BigDecimal("1") / 11, debit.gst_ratio
    assert_equal "debit", debit.direction
    assert_equal BigDecimal("3000"), credit.amount
    assert_equal BigDecimal("0"), credit.gst_ratio
    assert_equal "credit", credit.direction
  end

  test "recognizes standard aliases and GST text without losing the transaction sign" do
    upload = tdk_csv_upload(<<~CSV, filename: "prior-quarter.csv")
      Description,Account Name,Gross Amount,GST Amount
      Adobe subscription,Software & subscriptions,-121.00,GST included
      Bank interest,Interest,25.00,GST Free
      Footer total,,96.00,8.73
    CSV

    result = reader_for(upload).call

    assert result.success?, result.errors.to_sentence
    assert_equal 2, result.rows.length
    assert_equal BigDecimal("-11"), result.rows.first.gst_amount
    assert_equal BigDecimal("1") / 11, result.rows.first.gst_ratio
    assert_equal "taxable", result.rows.first.gst_treatment
    assert_equal BigDecimal("0"), result.rows.second.gst_amount
    assert_equal "gst_free", result.rows.second.gst_treatment
  end

  test "returns UI-ready mapping metadata for equally ranked ambiguous headers and accepts a confirmed override" do
    upload = tdk_csv_upload(<<~CSV, filename: "ambiguous.csv")
      Date,Transaction Date,Description,Description,Category,Amount,GST
      01/04/2026,01/04/2026,Adobe AU,Adobe subscription,Software,-121.00,-11.00
    CSV

    detected = reader_for(upload).call

    assert detected.needs_mapping?
    detection = detected.metadata.fetch("column_detection")
    assert_equal 1, detection.fetch("header_row_number")
    assert_equal 2, detection.fetch("data_start_row")
    assert_equal 7, detection.fetch("columns").length
    description_column = detection.fetch("columns").find { |column| column.fetch("source_column") == 3 }
    assert_equal 3, description_column.fetch("index")
    assert_equal "Description", description_column.fetch("source_header")
    assert_equal [ "Adobe AU" ], description_column.fetch("samples")
    assert_equal "category", detection.fetch("suggested_mapping").fetch("5")
    assert_equal "Adobe AU", detection.fetch("preview_rows").first.fetch("values").fetch(2)

    confirmed = reader_for(
      upload,
      mapping_override: {
        "header_row_number" => 1,
        "data_start_row" => 2,
        "columns" => {
          "description" => 4,
          "category" => 5,
          "amount" => 6,
          "gst" => 7
        }
      }
    ).call

    assert confirmed.success?, confirmed.errors.to_sentence
    assert_equal "Adobe subscription", confirmed.rows.first.description
    assert_equal "Software", confirmed.rows.first.category
    assert_equal 4, confirmed.column_mapping.fetch("description")
  end

  test "prefers an exact standard header over a more generic alias" do
    upload = tdk_csv_upload(<<~CSV, filename: "standard-header-priority.csv")
      Date,Category,Details,Total Amount,GST,Net amount,Description,Balance
      01/04/2026,Software,Adobe,-121.00,-11.00,-110.00,Adobe Creative Cloud,1000.00
    CSV

    result = reader_for(upload).call

    assert result.success?, result.errors.to_sentence
    assert_equal 7, result.column_mapping.fetch("description")
    assert_equal "Adobe Creative Cloud", result.rows.first.description
  end

  test "optional duplicate date headers do not force mapping confirmation" do
    upload = tdk_csv_upload(<<~CSV, filename: "duplicate-dates.csv")
      Date,Transaction Date,Description,Category,Amount
      01/04/2026,01/04/2026,Account fee,Bank fees,-10.00
    CSV

    result = reader_for(upload).call

    assert result.success?, result.errors.to_sentence
    assert_equal 1, result.rows.length
  end

  test "a confirmed mapping can select a populated category column whose header cell is blank" do
    upload = tdk_csv_upload(<<~CSV, filename: "blank-category-header.csv")
      Date,Description,Amount,GST,Balance,Notes,
      01/04/2026,Adobe Creative Cloud,-121.00,-11.00,1000.00,,Software
    CSV

    detected = reader_for(upload).call
    assert detected.needs_mapping?
    assert_equal "", detected.metadata.fetch("column_detection").fetch("columns").last.fetch("source_header")

    confirmed = reader_for(
      upload,
      mapping_override: {
        "header_row_number" => 1,
        "data_start_row" => 2,
        "columns" => { "description" => 2, "category" => 7, "amount" => 3, "gst" => 4 }
      }
    ).call

    assert confirmed.success?, confirmed.errors.to_sentence
    assert_equal "Software", confirmed.rows.first.category
    assert_equal 7, confirmed.column_mapping.fetch("category")
  end

  test "rejects source files beyond the safe column cap" do
    headers = Array.new(BasTdk::ReferenceWorkbookReader::MAX_COLUMNS + 1) { |index| "Column #{index + 1}" }
    upload = tdk_csv_upload("#{headers.join(',')}\n#{Array.new(headers.length, 'x').join(',')}\n", filename: "too-wide.csv")

    result = reader_for(upload).call

    assert_equal "failed", result.status
    assert_includes result.errors.to_sentence, "128 column limit"
  end

  private

  def reader_for(upload, mapping_override: nil)
    BasTdk::ReferenceWorkbookReader.new(
      path: upload.path,
      source_filename: upload.original_filename,
      mapping_override: mapping_override
    )
  end
end
