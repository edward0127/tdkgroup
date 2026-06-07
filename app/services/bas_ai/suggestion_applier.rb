require "bigdecimal"

module BasAi
  class SuggestionApplier
    class LockedJobError < StandardError; end
    class UnsupportedSuggestionError < StandardError; end

    LOW_CONFIDENCE_THRESHOLD = BigDecimal("85")

    def initialize(suggestion:, actor_username:)
      @suggestion = suggestion
      @bas_job = suggestion.bas_job
      @actor_username = actor_username
    end

    def accept!
      raise LockedJobError, "locked BAS jobs cannot apply AI suggestions" if bas_job.locked?

      ApplicationRecord.transaction do
        apply_suggestion_data
        suggestion.update!(
          status: "accepted",
          accepted_at: Time.current,
          accepted_by: actor_username
        )
        create_audit_event("bas_ai_suggestion_accepted")
      end

      suggestion
    end

    def reject!
      raise LockedJobError, "locked BAS jobs cannot reject AI suggestions" if bas_job.locked?

      suggestion.update!(
        status: "rejected",
        rejected_at: Time.current,
        rejected_by: actor_username
      )
      create_audit_event("bas_ai_suggestion_rejected")
      suggestion
    end

    def mark_needs_review!
      raise LockedJobError, "locked BAS jobs cannot mark AI suggestions for review" if bas_job.locked?

      suggestion.update!(status: "needs_review")
      create_review_query
      create_audit_event("bas_ai_suggestion_needs_review")
      suggestion
    end

    private

    attr_reader :suggestion, :bas_job, :actor_username

    def apply_suggestion_data
      case suggestion.suggestion_type
      when "invoice_extraction"
        apply_invoice_extraction
      when "gst_code"
        apply_gst_code
      when "query"
        apply_query
      when "match"
        apply_match
      when "summary"
        nil
      else
        raise UnsupportedSuggestionError, "Unsupported AI suggestion type"
      end
    end

    def apply_invoice_extraction
      data = suggestion.suggested_data
      gst_code = allowed_value(data["suggested_gst_code"], BasInvoice::GST_CODE_VALUES, "needs_review")
      status = review_needed?(data) ? "needs_review" : "imported"

      bas_job.invoices.create!(
        direction: invoice_direction(data["document_type"]),
        invoice_number: data["invoice_number"],
        issue_date: parse_date(data["issue_date"]),
        party_name: data["supplier_or_customer_name"],
        total_amount: parse_money(data["total_amount"]),
        gst_amount: parse_money(data["gst_amount"]),
        payment_method: allowed_value(data["payment_method"], BasInvoice::PAYMENT_METHOD_VALUES, "unknown"),
        gst_code: gst_code,
        status: status,
        notes: "Created from accepted AI extraction suggestion ##{suggestion.id}. Accountant review required."
      )
    end

    def apply_gst_code
      data = suggestion.suggested_data
      record = source_record(data["source_type"], data["source_id"])
      raise UnsupportedSuggestionError, "AI GST suggestions can only update invoices or cash transactions" unless record.is_a?(BasInvoice) || record.is_a?(BasCashTransaction)

      gst_code = allowed_value(data["suggested_gst_code"], record.class::GST_CODE_VALUES, "needs_review")
      attributes = { gst_code: gst_code }
      attributes[:status] = "needs_review" if review_needed?(data) || gst_code == "needs_review"
      record.update!(attributes)
    end

    def apply_query
      data = suggestion.suggested_data
      query_type = allowed_value(data["query_type"], BasQuery::QUERY_TYPE_VALUES, "other")
      related_source_type = data["related_source_type"].presence
      related_source_id = data["related_source_id"].presence
      dedupe_key = "ai_suggestion:#{suggestion.id}:query"

      bas_job.queries.find_or_create_by!(dedupe_key: dedupe_key) do |query|
        query.query_type = query_type
        query.status = "open"
        query.title = data["title"].presence || "AI suggested query"
        query.details = data["details"]
        query.created_by = actor_username
        query.updated_by = actor_username
        query.source_type = related_source_type
        query.source_id = related_source_id
        query.generated_by_rule = "ai_suggestion"
        query.auto_generated = true
      end
    end

    def apply_match
      data = suggestion.suggested_data
      source_ids = data["source_ids"].is_a?(Hash) ? data["source_ids"] : {}
      match = bas_job.matches.create!(
        match_type: allowed_value(data["suggested_match_type"], BasMatch::MATCH_TYPE_VALUES, "manual"),
        status: review_needed?(data) ? "needs_review" : "proposed",
        confidence: suggestion.confidence,
        matched_amount: parse_money(data["matched_amount"]),
        explanation: data["explanation"],
        created_by_rule: "ai_suggestion",
        notes: "Created from accepted AI match suggestion ##{suggestion.id}. Accountant review required."
      )

      Array(source_ids["invoice_ids"]).each do |id|
        invoice = bas_job.invoices.find_by(id: id)
        match.items.create!(matchable: invoice, amount: invoice.total_amount) if invoice
      end
      if source_ids["bank_transaction_id"].present?
        transaction = bas_job.bank_transactions.find_by(id: source_ids["bank_transaction_id"])
        match.items.create!(matchable: transaction, amount: transaction.amount) if transaction
      elsif source_ids["cash_transaction_id"].present?
        transaction = bas_job.cash_transactions.find_by(id: source_ids["cash_transaction_id"])
        match.items.create!(matchable: transaction, amount: transaction.total_amount) if transaction
      end
    end

    def create_review_query
      bas_job.queries.find_or_create_by!(dedupe_key: "ai_suggestion:#{suggestion.id}:needs_review") do |query|
        query.query_type = "other"
        query.status = "open"
        query.title = "AI suggestion needs review"
        query.details = "AI suggestion ##{suggestion.id} was marked needs review by an admin."
        query.created_by = actor_username
        query.updated_by = actor_username
        query.source_type = "BasAiSuggestion"
        query.source_id = suggestion.id
        query.generated_by_rule = "ai_suggestion_needs_review"
        query.auto_generated = true
      end
    end

    def source_record(source_type, source_id)
      case source_type
      when "BasInvoice"
        bas_job.invoices.find_by(id: source_id)
      when "BasCashTransaction"
        bas_job.cash_transactions.find_by(id: source_id)
      else
        nil
      end
    end

    def review_needed?(data)
      return true if data["needs_review"] == true
      return true if Array(data["missing_fields"]).any?
      return true if confidence < LOW_CONFIDENCE_THRESHOLD

      false
    end

    def confidence
      return BigDecimal("0") if suggestion.confidence.blank?

      BigDecimal(suggestion.confidence.to_s)
    end

    def invoice_direction(document_type)
      case document_type.to_s
      when "sales_invoice" then "sale"
      when "supplier_invoice", "receipt" then "purchase"
      else "unknown"
      end
    end

    def allowed_value(value, allowlist, fallback)
      allowlist.include?(value.to_s) ? value.to_s : fallback
    end

    def parse_money(value)
      BasImports::AmountParser.parse(value)
    end

    def parse_date(value)
      BasImports::DateParser.parse(value)
    end

    def create_audit_event(event_type)
      BasAuditEvent.create!(
        bas_job: bas_job,
        auditable: suggestion,
        event_type: event_type,
        actor_username: actor_username,
        metadata: {
          bas_ai_suggestion_id: suggestion.id,
          bas_ai_extraction_run_id: suggestion.bas_ai_extraction_run_id,
          suggestion_type: suggestion.suggestion_type,
          status: suggestion.status,
          confidence: suggestion.confidence&.to_s,
          provider: suggestion.bas_ai_extraction_run.provider,
          model_name: suggestion.bas_ai_extraction_run.ai_model_name
        }
      )
    end
  end
end
