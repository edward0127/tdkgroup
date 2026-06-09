require "csv"

module BasReports
  class CsvExporter
    FORMULA_PREFIXES = [ "=", "+", "-", "@" ].freeze

    def initialize(snapshot:)
      @snapshot = snapshot
      @totals = snapshot.totals.is_a?(Hash) ? snapshot.totals : {}
    end

    def summary_csv
      summary = totals.fetch("summary", {})
      labels = summary.fetch("bas_labels", {})
      payroll = totals.fetch("payroll", {})

      generate(headers: [ "Section", "Label", "Exact amount", "BAS label" ]) do |csv|
        csv << [ "GST", "G1 total sales", summary["g1_total_sales"], labels["G1"] ]
        csv << [ "GST", "1A GST on sales", summary["gst_on_sales_1a"], labels["1A"] ]
        csv << [ "GST", "1B GST on purchases", summary["gst_on_purchases_1b"], labels["1B"] ]
        csv << [ "GST", "Net GST payable/refundable", summary["net_gst_payable"], labels["net_gst_payable"] ]
        csv << [ "Payroll", "Gross wages", payroll["gross_wages"], nil ]
        csv << [ "Payroll", "PAYG withheld", payroll["payg_withheld"], nil ]
        csv << [ "Payroll", "Super amount", payroll["super_amount"], nil ]
      end
    end

    def gst_detail_csv
      generate(headers: [ "Section", "Source", "Source ID", "Date", "Direction", "Party", "Reference", "Description", "GST code", "Total amount", "GST amount", "Calculation source" ]) do |csv|
        Array(totals["gst_sales_detail"]).each do |row|
          csv << detail_row("Sales", row)
        end
        Array(totals["gst_purchase_detail"]).each do |row|
          csv << detail_row("Purchases", row)
        end
        Array(totals["cash_transaction_detail"]).each do |row|
          csv << detail_row("Cash transactions", row)
        end
        Array(totals["adjustments"]).each do |row|
          csv << [
            "Adjustments",
            "BasAdjustment",
            row["id"],
            nil,
            row["adjustment_type"],
            nil,
            row["label"],
            row["reason"],
            nil,
            row["amount"],
            nil,
            "manual_adjustment"
          ]
        end
      end
    end

    def breakdown_csv(label:)
      breakdown = BasReports::Breakdown.new(snapshot: snapshot, label: label).call

      generate(headers: [ "BAS label", "Section", "Source", "Source ID", "Date", "Reference", "Party", "Description", "Total amount", "GST amount", "Included amount", "GST code", "Status", "Linked records", "Related queries", "Reason" ]) do |csv|
        if breakdown.formula.present?
          csv << [
            breakdown.heading,
            "Formula",
            nil,
            nil,
            nil,
            nil,
            nil,
            "#{breakdown.formula['left_label']} #{breakdown.formula['operator']} #{breakdown.formula['right_label']}",
            breakdown.formula["left_amount"],
            breakdown.formula["right_amount"],
            breakdown.formula["result_amount"],
            nil,
            nil,
            nil,
            nil,
            "Net GST = 1A GST on sales - 1B GST on purchases"
          ]
        end

        breakdown.included_records.each do |row|
          csv << breakdown_row(breakdown.heading, "Included in this BAS figure", row)
        end

        breakdown.manual_adjustments.each do |row|
          csv << [
            breakdown.heading,
            "Manual adjustments included",
            "BasAdjustment",
            row["id"],
            nil,
            row["label"],
            row["created_by"],
            row["reason"],
            nil,
            nil,
            row["included_amount"],
            nil,
            row["adjustment_type"],
            nil,
            nil,
            row["reason_included"]
          ]
        end

        breakdown.excluded_records.each do |row|
          csv << breakdown_row(breakdown.heading, "Excluded / ignored", row)
        end

        breakdown.unresolved_records.each do |row|
          csv << breakdown_row(breakdown.heading, "Unmatched or unresolved records not included", row)
        end
      end
    end

    def matches_csv
      generate(headers: [ "Match ID", "Type", "Matched amount", "Accepted by", "Accepted at", "Items" ]) do |csv|
        Array(totals["accepted_matches"]).each do |match|
          csv << [
            match["id"],
            match["match_type"],
            match["matched_amount"],
            match["accepted_by"],
            match["accepted_at"],
            Array(match["items"]).map { |item| "#{item['source']}##{item['source_id']} #{item['amount']}" }.join("; ")
          ]
        end
      end
    end

    def queries_csv
      generate(headers: [ "Query ID", "Type", "Status", "Title", "Auto generated", "Source type", "Source ID" ]) do |csv|
        Array(totals["queries"]).each do |query|
          csv << [
            query["id"],
            query["query_type"],
            query["status"],
            query["title"],
            query["auto_generated"],
            query["source_type"],
            query["source_id"]
          ]
        end
      end
    end

    def adjustments_csv
      generate(headers: [ "Adjustment ID", "Type", "Label", "Amount", "Reason", "Created by" ]) do |csv|
        Array(totals["adjustments"]).each do |adjustment|
          csv << [
            adjustment["id"],
            adjustment["adjustment_type"],
            adjustment["label"],
            adjustment["amount"],
            adjustment["reason"],
            adjustment["created_by"]
          ]
        end
      end
    end

    private

    attr_reader :snapshot, :totals

    def detail_row(section, row)
      [
        section,
        row["source"],
        row["source_id"],
        row["date"],
        row["direction"],
        row["party"],
        row["reference"],
        row["description"],
        row["gst_code"],
        row["total_amount"],
        row["gst_amount"],
        row["calculation_source"]
      ]
    end

    def breakdown_row(label, section, row)
      [
        label,
        section,
        row["source"],
        row["source_id"],
        row["date"],
        row["reference"],
        row["party"],
        row["description"],
        row["total_amount"],
        row["gst_amount"],
        row["included_amount"],
        row["gst_code"],
        row["match_status"] || row["status"],
        Array(row["linked_records"]).map { |record| "#{record['source']}##{record['source_id']} via match ##{record['match_id']}" }.join("; "),
        Array(row["related_queries"]).map { |query| "Query ##{query['id']} #{query['status']}" }.join("; "),
        row["reason"]
      ]
    end

    def generate(headers:)
      CSV.generate(headers: true) do |csv|
        csv << headers.map { |header| safe_cell(header) }
        proxy = CsvProxy.new(csv, method(:safe_cell))
        yield proxy
      end
    end

    def safe_cell(value)
      string = value.to_s
      return string if string.blank?

      FORMULA_PREFIXES.include?(string[0]) ? "'#{string}" : string
    end

    class CsvProxy
      def initialize(csv, sanitizer)
        @csv = csv
        @sanitizer = sanitizer
      end

      def <<(row)
        @csv << row.map { |value| @sanitizer.call(value) }
      end
    end
  end
end
