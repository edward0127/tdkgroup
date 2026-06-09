require "bigdecimal"
require "set"

module BasReports
  class Breakdown
    class UnknownLabelError < StandardError; end

    Result = Data.define(
      :key,
      :heading,
      :summary_label,
      :exact_amount,
      :bas_label,
      :basis_note,
      :included_records,
      :manual_adjustments,
      :excluded_records,
      :unresolved_records,
      :formula
    )

    LABELS = {
      "g1" => {
        heading: "G1 total sales",
        amount_key: "g1_total_sales",
        bas_label_key: "G1",
        adjustment_types: %w[total_sales]
      },
      "1a" => {
        heading: "1A GST on sales",
        amount_key: "gst_on_sales_1a",
        bas_label_key: "1A",
        adjustment_types: %w[gst_on_sales]
      },
      "1b" => {
        heading: "1B GST on purchases",
        amount_key: "gst_on_purchases_1b",
        bas_label_key: "1B",
        adjustment_types: %w[gst_on_purchases]
      },
      "net_gst" => {
        heading: "Net GST payable/refundable",
        amount_key: "net_gst_payable",
        bas_label_key: "net_gst_payable",
        adjustment_types: %w[gst_on_sales gst_on_purchases]
      }
    }.freeze

    LABEL_ALIASES = {
      "g1" => "g1",
      "1a" => "1a",
      "1b" => "1b",
      "net" => "net_gst",
      "net_gst" => "net_gst",
      "net_gst_payable" => "net_gst"
    }.freeze

    REVIEW_GST_CODES = %w[unknown needs_review].freeze
    OPEN_QUERY_STATUSES = %w[open waiting_for_client].freeze

    def self.label_options
      LABELS.map { |key, config| [ key, config.fetch(:heading) ] }
    end

    def initialize(snapshot:, label:)
      @snapshot = snapshot
      @bas_job = snapshot.bas_job
      @totals = snapshot.totals.is_a?(Hash) ? snapshot.totals : {}
      @key = LABEL_ALIASES[label.to_s.downcase]
    end

    def call
      raise UnknownLabelError, "Unknown BAS breakdown label" if config.blank?

      Result.new(
        key: key,
        heading: config.fetch(:heading),
        summary_label: config.fetch(:amount_key),
        exact_amount: summary[config.fetch(:amount_key)],
        bas_label: summary.fetch("bas_labels", {})[config.fetch(:bas_label_key)],
        basis_note: basis_note,
        included_records: included_records,
        manual_adjustments: manual_adjustments,
        excluded_records: excluded_records,
        unresolved_records: unresolved_records,
        formula: formula
      )
    end

    private

    attr_reader :snapshot, :bas_job, :totals, :key

    def config
      LABELS[key]
    end

    def summary
      totals.fetch("summary", {})
    end

    def basis_note
      case snapshot_gst_basis
      when "cash"
        "Cash basis: figures are based on paid/matched transactions where applicable."
      when "accrual"
        "Accrual basis: figures are based on invoice issue/accrual records where applicable."
      else
        "GST basis is not set for this snapshot; calculation may be blocked."
      end
    end

    def snapshot_gst_basis
      totals.fetch("job", {})["gst_basis"].presence || bas_job.gst_basis
    end

    def included_records
      @included_records ||= case key
      when "g1"
        sales_invoice_rows("total_amount", "Sale total included in G1") +
          cash_rows("cash_receipt", "total_amount", "Cash sale total included in G1")
      when "1a"
        taxable_rows(sales_invoice_rows("gst_amount", "Taxable sale GST included in 1A")) +
          taxable_rows(cash_rows("cash_receipt", "gst_amount", "Taxable cash sale GST included in 1A"))
      when "1b"
        taxable_rows(purchase_invoice_rows("gst_amount", "Taxable purchase GST credit included in 1B")) +
          taxable_rows(cash_rows("cash_payment", "gst_amount", "Taxable cash purchase GST credit included in 1B"))
      else
        []
      end
    end

    def sales_invoice_rows(included_amount_key, reason)
      Array(totals["gst_sales_detail"]).filter_map do |row|
        next unless BasReports::Calculator::GST_INCLUDED_SALE_CODES.include?(row["gst_code"]) || key == "1a"

        build_included_record(row, included_amount_key: included_amount_key, reason: reason)
      end
    end

    def purchase_invoice_rows(included_amount_key, reason)
      Array(totals["gst_purchase_detail"]).map do |row|
        build_included_record(row, included_amount_key: included_amount_key, reason: reason)
      end
    end

    def cash_rows(direction, included_amount_key, reason)
      Array(totals["cash_transaction_detail"]).filter_map do |row|
        next unless row["direction"] == direction
        next unless BasReports::Calculator::GST_INCLUDED_SALE_CODES.include?(row["gst_code"]) || key.in?(%w[1a 1b])

        build_included_record(row, included_amount_key: included_amount_key, reason: reason)
      end
    end

    def taxable_rows(rows)
      rows.select { |row| row["gst_code"] == "taxable" }
    end

    def build_included_record(row, included_amount_key:, reason:)
      source_type = row["source"].to_s
      source_id = row["source_id"].to_i
      record = source_record_for(source_type, source_id)

      {
        "source" => source_type,
        "source_id" => source_id,
        "source_type_label" => source_type_label(source_type),
        "source_label" => source_record_label(source_type, source_id, record),
        "date" => row["date"],
        "reference" => row["reference"].presence || source_reference(record),
        "party" => row["party"].presence || source_party(record),
        "description" => row["description"].presence || source_description(record),
        "gst_code" => row["gst_code"],
        "total_amount" => row["total_amount"],
        "gst_amount" => row["gst_amount"],
        "included_amount" => row[included_amount_key],
        "match_status" => match_status_for(source_type, source_id, record),
        "linked_records" => linked_records_for(source_type, source_id),
        "related_queries" => related_queries_for(source_type, source_id),
        "reason" => [ reason, calculation_source_reason(row["calculation_source"]) ].compact.join(" - ")
      }
    end

    def manual_adjustments
      @manual_adjustments ||= Array(totals["adjustments"]).filter_map do |adjustment|
        next unless config.fetch(:adjustment_types).include?(adjustment["adjustment_type"])

        {
          "id" => adjustment["id"],
          "source" => "BasAdjustment",
          "source_id" => adjustment["id"],
          "adjustment_type" => adjustment["adjustment_type"],
          "adjustment_type_label" => adjustment["adjustment_type"].to_s.humanize,
          "label" => adjustment["label"],
          "amount" => adjustment["amount"],
          "included_amount" => adjustment["amount"],
          "reason" => adjustment["reason"],
          "created_by" => adjustment["created_by"],
          "reason_included" => adjustment_inclusion_reason(adjustment["adjustment_type"])
        }
      end
    end

    def excluded_records
      @excluded_records ||= Array(totals["ignored_items"]).filter_map do |item|
        source_type = item["source"].to_s
        source_id = item["source_id"].to_i
        record = source_record_for(source_type, source_id)
        next unless relevant_source?(source_type, record)

        {
          "source" => source_type,
          "source_id" => source_id,
          "source_type_label" => source_type_label(source_type),
          "source_label" => source_record_label(source_type, source_id, record),
          "date" => source_date(record),
          "reference" => source_reference(record),
          "party" => source_party(record),
          "description" => source_description(record),
          "total_amount" => source_total_amount(record),
          "gst_amount" => source_gst_amount(record),
          "gst_code" => item["gst_code"].presence || record_gst_code(record),
          "status" => item["status"].presence || record_status(record),
          "reason" => excluded_reason(item, record)
        }
      end
    end

    def unresolved_records
      @unresolved_records ||= begin
        source_rows = unresolved_source_records
        query_rows = unresolved_query_records(source_rows)

        (source_rows + query_rows).uniq { |row| [ row["source"], row["source_id"], row["query_id"] ] }
      end
    end

    def unresolved_source_records
      current_unresolved_candidates.filter_map do |record|
        source_type = record.class.name
        source_id = record.id
        next if included_source_keys.include?([ source_type, source_id ])
        next unless relevant_source?(source_type, record)
        next unless unresolved_record?(record)

        {
          "source" => source_type,
          "source_id" => source_id,
          "source_type_label" => source_type_label(source_type),
          "source_label" => source_record_label(source_type, source_id, record),
          "date" => source_date(record),
          "reference" => source_reference(record),
          "party" => source_party(record),
          "description" => source_description(record),
          "total_amount" => source_total_amount(record),
          "gst_amount" => source_gst_amount(record),
          "gst_code" => record_gst_code(record),
          "status" => record_status(record),
          "related_queries" => related_queries_for(source_type, source_id),
          "reason" => unresolved_reason(record)
        }
      end
    end

    def unresolved_query_records(existing_rows)
      existing_source_keys = existing_rows.map { |row| [ row["source"], row["source_id"] ] }.to_set

      snapshot_queries.filter_map do |query|
        next unless OPEN_QUERY_STATUSES.include?(query["status"])

        source_type = query["source_type"].to_s
        source_id = query["source_id"].to_i
        record = source_record_for(source_type, source_id)
        next if source_type.present? && source_id.positive? && existing_source_keys.include?([ source_type, source_id ])
        next if source_type.present? && !relevant_source?(source_type, record)

        {
          "source" => source_type.presence || "BasQuery",
          "source_id" => source_id.positive? ? source_id : query["id"],
          "source_type_label" => source_type.present? ? source_type_label(source_type) : "BAS query",
          "source_label" => source_type.present? ? source_record_label(source_type, source_id, record) : "Query ##{query['id']}",
          "date" => source_date(record),
          "reference" => source_reference(record),
          "party" => source_party(record),
          "description" => query["title"],
          "total_amount" => source_total_amount(record),
          "gst_amount" => source_gst_amount(record),
          "gst_code" => record_gst_code(record),
          "status" => query["status"],
          "query_id" => query["id"],
          "related_queries" => [ query_summary(query) ],
          "reason" => "Open BAS query not resolved when this snapshot was generated"
        }
      end
    end

    def current_unresolved_candidates
      records = []
      records.concat(active_invoices.to_a)
      records.concat(active_cash_transactions.to_a)
      records.concat(bas_job.bank_transactions.unmatched.to_a)
      records
    end

    def active_invoices
      bas_job.invoices.where.not(status: "ignored").where.not(gst_code: "bas_excluded")
    end

    def active_cash_transactions
      bas_job.cash_transactions.where.not(status: "ignored").where.not(gst_code: "bas_excluded")
    end

    def relevant_source?(source_type, record)
      return true if key == "net_gst"

      case source_type
      when "BasInvoice"
        direction = record&.direction.to_s
        return direction.in?(%w[sale unknown]) if key.in?(%w[g1 1a])

        direction.in?(%w[purchase unknown])
      when "BasCashTransaction"
        direction = record&.direction.to_s
        return direction.in?(%w[cash_receipt unknown]) if key.in?(%w[g1 1a])

        direction.in?(%w[cash_payment unknown])
      when "BasBankTransaction"
        snapshot_gst_basis == "cash"
      else
        false
      end
    end

    def unresolved_record?(record)
      return true if record_status(record) == "needs_review"
      return true if REVIEW_GST_CODES.include?(record_gst_code(record))
      return true if record.respond_to?(:direction) && record.direction == "unknown"
      return true if record.is_a?(BasBankTransaction) && record.status != "matched"
      return true if cash_basis_invoice_without_accepted_match?(record)
      return true if related_queries_for(record.class.name, record.id).any? { |query| OPEN_QUERY_STATUSES.include?(query["status"]) }

      false
    end

    def cash_basis_invoice_without_accepted_match?(record)
      return false unless snapshot_gst_basis == "cash"
      return false unless record.is_a?(BasInvoice)
      return false unless record.direction.in?(%w[sale purchase])

      accepted_matches_for(record.class.name, record.id).blank?
    end

    def unresolved_reason(record)
      return "Record is marked needs review" if record_status(record) == "needs_review"
      return "GST treatment needs review" if REVIEW_GST_CODES.include?(record_gst_code(record))
      return "Direction is unknown" if record.respond_to?(:direction) && record.direction == "unknown"
      return "Unmatched bank transaction not used in BAS figures" if record.is_a?(BasBankTransaction)
      return "Cash basis invoice has no accepted payment match in this snapshot" if cash_basis_invoice_without_accepted_match?(record)

      "Open BAS query not resolved when this snapshot was generated"
    end

    def formula
      return nil unless key == "net_gst"

      {
        "left_label" => "1A GST on sales",
        "left_amount" => summary["gst_on_sales_1a"],
        "operator" => "-",
        "right_label" => "1B GST on purchases",
        "right_amount" => summary["gst_on_purchases_1b"],
        "result_label" => "Net GST payable/refundable",
        "result_amount" => summary["net_gst_payable"]
      }
    end

    def included_source_keys
      @included_source_keys ||= included_records.map { |row| [ row["source"], row["source_id"] ] }.to_set
    end

    def calculation_source_reason(source)
      case source
      when "cash_basis_match"
        "cash basis accepted match in the BAS period"
      when "accrual_issue_date"
        "accrual basis invoice issue date in the BAS period"
      else
        "source transaction date in the BAS period"
      end
    end

    def adjustment_inclusion_reason(adjustment_type)
      case [ key, adjustment_type ]
      when [ "g1", "total_sales" ]
        "Manual adjustment included in G1 total sales"
      when [ "1a", "gst_on_sales" ]
        "Manual adjustment included in 1A GST on sales"
      when [ "1b", "gst_on_purchases" ]
        "Manual adjustment included in 1B GST on purchases"
      when [ "net_gst", "gst_on_sales" ]
        "Manual adjustment included through 1A before the net GST formula"
      when [ "net_gst", "gst_on_purchases" ]
        "Manual adjustment included through 1B before the net GST formula"
      else
        "Manual adjustment included in this snapshot"
      end
    end

    def excluded_reason(item, record)
      status = item["status"].presence || record_status(record)
      gst_code = item["gst_code"].presence || record_gst_code(record)

      return "Record status is ignored" if status == "ignored"
      return "GST code is BAS-excluded" if gst_code == "bas_excluded"

      "Record was not included in this BAS snapshot"
    end

    def match_status_for(source_type, source_id, record)
      return "Accepted match" if accepted_matches_for(source_type, source_id).any?
      return record.status.humanize if record.respond_to?(:status) && record.status.present?

      "Not recorded"
    end

    def linked_records_for(source_type, source_id)
      accepted_matches_for(source_type, source_id).flat_map do |match|
        Array(match["items"]).filter_map do |item|
          next if item["source"].to_s == source_type && item["source_id"].to_i == source_id
          next unless item["source"].to_s.in?(%w[BasBankTransaction BasCashTransaction])

          linked_source_type = item["source"].to_s
          linked_source_id = item["source_id"].to_i
          linked_record = source_record_for(linked_source_type, linked_source_id)

          {
            "match_id" => match["id"],
            "source" => linked_source_type,
            "source_id" => linked_source_id,
            "source_type_label" => source_type_label(linked_source_type),
            "source_label" => source_record_label(linked_source_type, linked_source_id, linked_record),
            "amount" => item["amount"]
          }
        end
      end
    end

    def accepted_matches_for(source_type, source_id)
      matches_by_source.fetch([ source_type.to_s, source_id.to_i ], [])
    end

    def matches_by_source
      @matches_by_source ||= Hash.new { |hash, key| hash[key] = [] }.tap do |index|
        Array(totals["accepted_matches"]).each do |match|
          Array(match["items"]).each do |item|
            index[[ item["source"].to_s, item["source_id"].to_i ]] << match
          end
        end
      end
    end

    def related_queries_for(source_type, source_id)
      snapshot_queries.select do |query|
        query["source_type"].to_s == source_type.to_s && query["source_id"].to_i == source_id.to_i
      end.map { |query| query_summary(query) }
    end

    def snapshot_queries
      Array(totals["queries"])
    end

    def query_summary(query)
      {
        "id" => query["id"],
        "status" => query["status"],
        "title" => query["title"],
        "query_type" => query["query_type"]
      }
    end

    def source_record_for(source_type, source_id)
      source_records.fetch([ source_type.to_s, source_id.to_i ], nil)
    end

    def source_records
      @source_records ||= begin
        ids = source_ids
        records = {}

        if ids["BasInvoice"].any?
          bas_job.invoices.where(id: ids["BasInvoice"].to_a).find_each do |record|
            records[[ "BasInvoice", record.id ]] = record
          end
        end

        if ids["BasCashTransaction"].any?
          bas_job.cash_transactions.where(id: ids["BasCashTransaction"].to_a).find_each do |record|
            records[[ "BasCashTransaction", record.id ]] = record
          end
        end

        if ids["BasBankTransaction"].any?
          bas_job.bank_transactions.where(id: ids["BasBankTransaction"].to_a).find_each do |record|
            records[[ "BasBankTransaction", record.id ]] = record
          end
        end

        records
      end
    end

    def source_ids
      ids = Hash.new { |hash, key| hash[key] = Set.new }

      detail_rows.each do |row|
        ids[row["source"].to_s] << row["source_id"].to_i if row["source"].present? && row["source_id"].present?
      end

      Array(totals["ignored_items"]).each do |row|
        ids[row["source"].to_s] << row["source_id"].to_i if row["source"].present? && row["source_id"].present?
      end

      Array(totals["accepted_matches"]).each do |match|
        Array(match["items"]).each do |item|
          ids[item["source"].to_s] << item["source_id"].to_i if item["source"].present? && item["source_id"].present?
        end
      end

      snapshot_queries.each do |query|
        ids[query["source_type"].to_s] << query["source_id"].to_i if query["source_type"].present? && query["source_id"].present?
      end

      ids
    end

    def detail_rows
      Array(totals["gst_sales_detail"]) +
        Array(totals["gst_purchase_detail"]) +
        Array(totals["cash_transaction_detail"])
    end

    def source_type_label(source_type)
      source_type.to_s.delete_prefix("Bas").titleize
    end

    def source_record_label(source_type, source_id, record)
      case record
      when BasInvoice
        record.invoice_number.presence || "Invoice ##{record.id}"
      when BasBankTransaction
        record.reference.presence || record.description.presence || "Bank transaction ##{record.id}"
      when BasCashTransaction
        record.party_name.presence || record.description.presence || "Cash transaction ##{record.id}"
      else
        "#{source_type_label(source_type)} ##{source_id}"
      end
    end

    def source_date(record)
      case record
      when BasInvoice
        record.issue_date&.to_fs(:db)
      when BasBankTransaction, BasCashTransaction
        record.transaction_date&.to_fs(:db)
      else
        nil
      end
    end

    def source_reference(record)
      case record
      when BasInvoice
        record.invoice_number
      when BasBankTransaction
        record.reference
      else
        nil
      end
    end

    def source_party(record)
      case record
      when BasInvoice, BasCashTransaction
        record.party_name
      else
        nil
      end
    end

    def source_description(record)
      case record
      when BasInvoice, BasBankTransaction, BasCashTransaction
        record.description
      else
        nil
      end
    end

    def source_total_amount(record)
      case record
      when BasInvoice, BasCashTransaction
        serialize_money(record.total_amount)
      when BasBankTransaction
        serialize_money(record.amount)
      else
        nil
      end
    end

    def source_gst_amount(record)
      return nil unless record.respond_to?(:gst_amount)

      serialize_money(record.gst_amount)
    end

    def record_status(record)
      record.respond_to?(:status) ? record.status : nil
    end

    def record_gst_code(record)
      record.respond_to?(:gst_code) ? record.gst_code : nil
    end

    def serialize_money(value)
      return nil if value.blank?

      amount = BigDecimal(value.to_s).round(2)
      sign = amount.negative? ? "-" : ""
      integer_part, decimal_part = amount.abs.to_s("F").split(".", 2)
      "#{sign}#{integer_part}.#{decimal_part.to_s.ljust(2, '0')[0, 2]}"
    end
  end
end
