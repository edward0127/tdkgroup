module BasPdfBankStatements
  class ConfidenceScorer
    Result = Data.define(:rows, :row_errors)

    def initialize(rows:)
      @rows = Array(rows)
    end

    def call
      scored_rows = rows.map { |row| score_row(row.deep_dup) }
      row_errors = scored_rows.select { |row| low_confidence?(row) }.map do |row|
        {
          "row_number" => row["row_number"],
          "message" => Array(row["warnings"]).join(", ")
        }
      end

      Result.new(rows: scored_rows, row_errors: row_errors)
    end

    private

    attr_reader :rows

    def score_row(row)
      warnings = []
      warnings << "Transaction date is missing or unclear." if row["transaction_date"].blank?
      warnings << "Description is missing or unclear." if row["description"].blank?
      warnings << "Amount is missing or unclear." if row["amount"].blank? && row["debit"].blank? && row["credit"].blank?
      warnings << "Balance was not detected." if row["balance"].blank?

      required_warning_count = warnings.count { |warning| warning.include?("missing or unclear") }
      confidence = 95 - (required_warning_count * 30)
      confidence -= 10 if row["balance"].blank?

      row["confidence"] = [ confidence, 0 ].max
      row["warnings"] = warnings
      row
    end

    def low_confidence?(row)
      row["confidence"].to_i < 70 || Array(row["warnings"]).any? { |warning| warning.include?("missing or unclear") }
    end
  end
end
