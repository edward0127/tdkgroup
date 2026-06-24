require "csv"
require "roo"
require "roo/base"
require "roo/excelx"

module BasImports
  class FileReader
    class UnsupportedFileError < StandardError; end
    class ReadError < StandardError; end

    Result = Struct.new(:headers, :rows, keyword_init: true)

    CSV_CONTENT_TYPES = %w[text/csv application/csv].freeze
    XLSX_CONTENT_TYPES = %w[application/vnd.openxmlformats-officedocument.spreadsheetml.sheet].freeze

    def self.read(document, limit: nil)
      new.read(document, limit: limit)
    end

    def read(document, limit: nil)
      raise ReadError, "document file is not attached" unless document.file.attached?

      case file_kind(document)
      when :csv
        read_csv(document.file.download, limit: limit)
      when :xlsx
        read_xlsx(document, limit: limit)
      else
        raise UnsupportedFileError, "unsupported import file type"
      end
    end

    private

    def file_kind(document)
      extension = File.extname(document.safe_filename).downcase
      content_type = document.file.blob.content_type.to_s

      return :csv if extension == ".csv" || CSV_CONTENT_TYPES.include?(content_type)
      return :xlsx if extension == ".xlsx" || XLSX_CONTENT_TYPES.include?(content_type)

      nil
    end

    def read_csv(content, limit:)
      csv = CSV.parse(content, headers: true, liberal_parsing: true)
      headers = csv.headers.compact.map { |header| header.to_s.delete_prefix("\uFEFF").strip }
      rows = []

      csv.each.with_index(2) do |row, row_number|
        data = headers.to_h { |header| [ header, row[header] ] }
        next if data.values.all?(&:blank?)

        rows << { "row_number" => row_number, "data" => data }
        break if limit.present? && rows.size >= limit
      end

      Result.new(headers: headers, rows: rows)
    rescue CSV::MalformedCSVError => e
      raise ReadError, "CSV could not be read: #{e.message}"
    end

    def read_xlsx(document, limit:)
      document.file.open do |file|
        workbook = Roo::Excelx.new(file.path)
        sheet = workbook.sheet(0)
        headers = Array(sheet.row(1)).map { |header| header.to_s.strip }.compact_blank
        rows = []

        (2..sheet.last_row.to_i).each do |row_number|
          data = headers.each_with_index.to_h do |header, index|
            [ header, raw_xlsx_value(sheet, row_number, index + 1) ]
          end
          next if data.values.all?(&:blank?)

          rows << { "row_number" => row_number, "data" => data }
          break if limit.present? && rows.size >= limit
        end

        Result.new(headers: headers, rows: rows)
      end
    rescue Roo::FileNotFound, Zip::Error, ArgumentError => e
      raise ReadError, "XLSX could not be read: #{e.message}"
    end

    def raw_xlsx_value(sheet, row_number, column_number)
      value = sheet.excelx_value(row_number, column_number)
      value = sheet.cell(row_number, column_number) if value.nil?
      value.to_s
    rescue RuntimeError => e
      raise unless custom_number_format_error?(e)

      raw_fallback_xlsx_value(sheet, row_number, column_number).to_s
    end

    def raw_fallback_xlsx_value(sheet, row_number, column_number)
      sheet.cell(row_number, column_number)
    rescue RuntimeError => e
      raise unless custom_number_format_error?(e)

      nil
    end

    def custom_number_format_error?(error)
      error.message.to_s.start_with?("Unknown format:")
    end
  end
end
