require "csv"

module BasPdfBankStatements
  class CsvBuilder
    HEADERS = [
      "Date",
      "Description",
      "Details",
      "Reference",
      "Debit",
      "Credit",
      "Amount",
      "Balance",
      "Bank Account Name"
    ].freeze

    FIELD_BY_HEADER = {
      "Date" => "transaction_date",
      "Description" => "description",
      "Details" => "details",
      "Reference" => "reference",
      "Debit" => "debit",
      "Credit" => "credit",
      "Amount" => "amount",
      "Balance" => "balance",
      "Bank Account Name" => "bank_account_name"
    }.freeze

    FORMULA_PREFIXES = [ "=", "+", "-", "@" ].freeze

    def initialize(rows:)
      @rows = Array(rows)
    end

    def call
      CSV.generate(headers: true, encoding: "UTF-8") do |csv|
        csv << HEADERS
        rows.each do |row|
          csv << HEADERS.map { |header| safe_cell(row[FIELD_BY_HEADER.fetch(header)]) }
        end
      end
    end

    private

    attr_reader :rows

    def safe_cell(value)
      string = value.to_s
      return string if string.blank?

      FORMULA_PREFIXES.include?(string[0]) ? "'#{string}" : string
    end
  end
end
