module BasTdk
  class BankStatementImporter
    class UnsupportedFileError < StandardError; end

    XLSX_CONTENT_TYPES = %w[
      application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    ].freeze
    PDF_CONTENT_TYPES = %w[
      application/pdf
    ].freeze
    CSV_CONTENT_TYPES = %w[
      text/csv
      application/csv
      application/vnd.ms-excel
    ].freeze
    CSV_EXTENSION_CONTENT_TYPES = (CSV_CONTENT_TYPES + %w[
      text/plain
      application/octet-stream
    ]).freeze
    SUPPORTED_UPLOAD_ERROR = "Only XLSX, CSV and bank statement PDF files are supported.".freeze

    def self.source_type(filename:, content_type:)
      extension = File.extname(filename.to_s).downcase
      normalized_content_type = content_type.to_s.downcase

      return :xlsx if extension == ".xlsx" || XLSX_CONTENT_TYPES.include?(normalized_content_type)
      return :pdf if extension == ".pdf" || PDF_CONTENT_TYPES.include?(normalized_content_type)
      return :csv if extension == ".csv" && (normalized_content_type.blank? || CSV_EXTENSION_CONTENT_TYPES.include?(normalized_content_type))

      nil
    end

    def self.supported_upload?(filename:, content_type:)
      source_type(filename: filename, content_type: content_type).present?
    end

    def initialize(source_type:, xlsx_parser:, pdf_parser:, csv_parser: nil)
      @source_type = source_type
      @xlsx_parser = xlsx_parser
      @pdf_parser = pdf_parser
      @csv_parser = csv_parser
    end

    def call
      case @source_type
      when :xlsx
        @xlsx_parser.call
      when :pdf
        @pdf_parser.call
      when :csv
        @csv_parser.call
      else
        raise UnsupportedFileError, SUPPORTED_UPLOAD_ERROR
      end
    end
  end
end
