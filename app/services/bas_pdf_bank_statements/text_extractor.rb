require "pdf/reader"

module BasPdfBankStatements
  class TextExtractor
    class ExtractionError < StandardError; end

    UNREADABLE_MESSAGE = "This PDF does not contain readable bank statement text. Please request CSV/XLSX from the client or manually prepare a bank statement import file.".freeze
    ENCRYPTED_MESSAGE = "This PDF is password-protected or encrypted. Please request CSV/XLSX from the client or manually prepare a bank statement import file.".freeze

    Result = Data.define(:text, :page_count)

    def initialize(bas_document:)
      @bas_document = bas_document
    end

    def call
      raise ExtractionError, "PDF file is not attached." unless bas_document.file.attached?

      bas_document.file.open do |file|
        reader = PDF::Reader.new(file.path)
        text = reader.pages.map(&:text).join("\n\n").scrub
        raise ExtractionError, UNREADABLE_MESSAGE if text.squish.blank?

        Result.new(text: text, page_count: reader.page_count)
      end
    rescue PDF::Reader::EncryptedPDFError
      raise ExtractionError, ENCRYPTED_MESSAGE
    rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError
      raise ExtractionError, UNREADABLE_MESSAGE
    end

    private

    attr_reader :bas_document
  end
end
