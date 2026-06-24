require "test_helper"
require "cgi"
require "nokogiri"
require "zip"
require_relative "../support/tdk_workbook_helper"

class BasTdkWorkbookExporterTest < ActiveSupport::TestCase
  include TdkWorkbookHelper

  test "exports familiar editable workbook with metadata headers typed values and formula protection" do
    workbook = create_workbook
    data = BasTdk::WorkbookExporter.new(workbook: workbook).call
    rows = tdk_downloaded_rows(data)
    table_rows = tdk_downloaded_table_rows(data)

    assert_equal "Synthetic Exporter Client Pty Ltd", rows.first.first
    assert_equal "BAS period", rows.second[0]
    assert_equal workbook.bas_job.period_label, rows.second[1]
    assert_equal "Source file", rows.second[2]
    assert_equal "synthetic-export.xlsx", rows.second[3]
    assert_equal "Exported", rows.second[4]
    assert_match(/\A\d{2}\/\d{2}\/\d{4} \d{2}:\d{2}\z/, rows.second[5])
    assert rows.third.all?(&:blank?), "row 3 should stay blank before the table header"
    assert_equal [ "Date", "Category", "Amount", "GST", "Description", "Details", "Reference" ], rows.fourth.first(7)
    assert_equal [ "Date", "Category", "Amount", "GST", "Description", "Details", "Reference" ], table_rows.first
    assert_equal "2026-02-16", table_rows.second[0]
    assert_equal "Meals", table_rows.second[1]
    assert_equal "-8671.67", table_rows.second[2]
    assert_equal "10.0", table_rows.second[3]
    assert_includes table_rows.second[4], "SUM"
    assert_equal "Reference 123", table_rows.second[6]

    workbook_xml = xlsx_xml(data)
    assert_not_includes workbook_xml, "<f>"
    assert_includes CGI.unescapeHTML(workbook_xml), "'=SUM(1,2)"
  end

  test "exports date and amount columns with Excel formats and real cell values" do
    workbook = create_workbook(amount: "-9762.950000000007")
    data = BasTdk::WorkbookExporter.new(workbook: workbook).call
    entries = xlsx_entries(data)
    styles_xml = entries.fetch("xl/styles.xml")
    sheet_doc = Nokogiri::XML(entries.fetch("xl/worksheets/sheet1.xml")) { |config| config.strict.noblanks }
    sheet_doc.remove_namespaces!

    assert_includes styles_xml, BasTdk::WorkbookExporter::DATE_FORMAT
    assert_includes styles_xml, BasTdk::WorkbookExporter::AMOUNT_FORMAT

    header_row = sheet_doc.at_xpath("//row[@r='4']")
    date_cell = sheet_doc.at_xpath("//c[@r='A5']")
    amount_cell = sheet_doc.at_xpath("//c[@r='C5']")
    gst_cell = sheet_doc.at_xpath("//c[@r='D5']")

    assert header_row, "table header should remain on row 4"
    assert date_cell.at_xpath("v").text.to_f.positive?
    assert_nil date_cell["t"], "date cell should be stored as a real Excel value"
    assert_equal "-9762.95", amount_cell.at_xpath("v").text
    assert_includes [ nil, "n" ], amount_cell["t"], "amount cell should be stored as a numeric value"
    assert_equal "10.0", gst_cell.at_xpath("v").text
    assert_includes [ nil, "n" ], gst_cell["t"], "numeric GST cell should be stored as a numeric value"
  end

  test "cleans decimal noise from exported text cells without changing references" do
    workbook = create_workbook
    row = workbook.rows.ordered.first
    row.update!(
      row_data: row.row_data.merge(
        "Details" => "8770.7199999999993",
        "Reference" => "7341056315"
      )
    )

    data = BasTdk::WorkbookExporter.new(workbook: workbook).call
    table_rows = tdk_downloaded_table_rows(data)

    assert_equal "8770.72", table_rows.second[5]
    assert_equal "7341056315", table_rows.second[6]
  end

  private

  def create_workbook(amount: "-8671.67")
    job = BasJob.create!(
      bas_client: BasClient.create!(legal_name: "Synthetic Exporter Client Pty Ltd"),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      workflow_type: "tdk_group"
    )
    workbook = BasTdkWorkbook.create!(
      bas_job: job,
      status: "processed",
      source_filename: "synthetic-export.xlsx",
      sheet_name: "Bank Report",
      header_row_number: 4,
      original_headers: [ "Date", "Amount", "Description" ],
      processed_headers: [ "Details", "Amount", "Date", "Reference", "Description", "Category", "GST" ],
      row_count: 1,
      version_number: 1,
      processed_at: Time.current,
      processed_by: "tdk-exporter-test"
    )
    workbook.rows.create!(
      position: 1,
      source_row_number: 5,
      row_data: {
        "Date" => "16/02/2026",
        "Category" => "Meals",
        "Amount" => amount,
        "GST" => "10.00",
        "Description" => "=SUM(1,2)",
        "Details" => "@danger",
        "Reference" => "Reference 123"
      }
    )
    workbook
  end

  def xlsx_xml(data)
    xlsx_entries(data).values.join("\n")
  end

  def xlsx_entries(data)
    Zip::File.open_buffer(data).each_with_object({}) do |entry, entries|
      next unless entry.name.end_with?(".xml")

      entries[entry.name] = entry.get_input_stream.read
    end
  end
end
