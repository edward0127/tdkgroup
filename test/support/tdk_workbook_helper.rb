require "caxlsx"
require "roo"
require "roo/base"
require "roo/excelx"
require "rack/test"
require "securerandom"
require "tempfile"
require_relative "synthetic_pdf_helper"

module TdkWorkbookHelper
  include SyntheticPdfHelper

  XLSX_CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze
  PDF_CONTENT_TYPE = "application/pdf".freeze
  TDK_ACCOUNTING_FORMAT = '#,##0.00;[Red]_(\ \(#,##0.00\)'.freeze

  def tdk_xlsx_upload(rows, filename: "synthetic-tdk-bank.xlsx", sheet_name: "Bank Report", accounting_format_columns: [])
    path = Rails.root.join("tmp", "#{SecureRandom.hex}-#{filename}")
    package = Axlsx::Package.new
    accounting_style = if accounting_format_columns.any?
      package.workbook.styles.add_style(format_code: TDK_ACCOUNTING_FORMAT)
    end

    package.workbook.add_worksheet(name: sheet_name) do |sheet|
      rows.each do |row|
        sheet.add_row(row, style: tdk_row_styles(row, accounting_format_columns, accounting_style))
      end
    end
    package.serialize(path.to_s)
    Rack::Test::UploadedFile.new(path.to_s, XLSX_CONTENT_TYPE, true, original_filename: filename)
  end

  def tdk_text_upload(content, filename: "synthetic-not-xlsx.txt", content_type: "text/plain")
    path = Rails.root.join("tmp", "#{SecureRandom.hex}-#{filename}")
    File.binwrite(path, content)
    Rack::Test::UploadedFile.new(path.to_s, content_type, true, original_filename: filename)
  end

  def tdk_pdf_upload(text, filename: "synthetic-tdk-bank.pdf")
    path = Rails.root.join("tmp", "#{SecureRandom.hex}-#{filename}")
    File.binwrite(path, synthetic_pdf(text))
    Rack::Test::UploadedFile.new(path.to_s, PDF_CONTENT_TYPE, true, original_filename: filename)
  end

  def tdk_downloaded_rows(binary)
    tempfile = Tempfile.new([ "tdk-download", ".xlsx" ])
    tempfile.binmode
    tempfile.write(binary)
    tempfile.close

    workbook = Roo::Excelx.new(tempfile.path)
    sheet = workbook.sheet(0)
    (1..sheet.last_row.to_i).map { |row_number| sheet.row(row_number).map(&:to_s) }
  ensure
    tempfile&.unlink
  end

  def tdk_downloaded_table_rows(binary)
    rows = tdk_downloaded_rows(binary)
    header_index = rows.index do |row|
      normalized = row.map { |value| value.to_s.downcase }
      normalized.include?("date") && normalized.include?("amount")
    end

    header_index.present? ? rows[header_index..] : rows
  end

  def tdk_row_styles(row, accounting_format_columns, accounting_style)
    return if accounting_style.blank?

    row.each_index.map do |index|
      accounting_format_columns.include?(index + 1) ? accounting_style : nil
    end
  end
end
