module BasTdk
  class CodingReviewReport
    REASON_DEFINITIONS = {
      uncertain_or_blank: {
        title: "Uncertain purchase or intentional blank",
        description: "The description does not identify the purchase reliably, so one or both fields were intentionally left blank for confirmation."
      },
      historical_gst_issue: {
        title: "Prior-quarter coding missing or inconsistent",
        description: "Prior-quarter evidence conflicts, or a Category match exists but its GST history is missing, incomplete or inconsistent."
      },
      rule_derived: {
        title: "Rule-derived suggestion",
        description: "The suggestion came from an accounting rule and needs the current tax invoice or business purpose checked."
      },
      prior_quarter_non_exact: {
        title: "Prior-quarter match needs confirmation",
        description: "The match is similar, merchant-based, template-based or has insufficient coded support for automatic acceptance."
      },
      unclassified: {
        title: "No reliable match",
        description: "Neither the prior-quarter file nor a safe rule supplied a reliable value, so manual coding is required."
      },
      other: {
        title: "Other review check",
        description: "The coding engine requested confirmation for a reason not covered by the more specific groups above."
      }
    }.freeze

    REASON_PRIORITY = %i[
      historical_gst_issue
      rule_derived
      uncertain_or_blank
      prior_quarter_non_exact
      unclassified
      other
    ].freeze
    HISTORICAL_GST_WARNING_CODES = %w[
      historical_gst_conflict
      historical_gst_missing
    ].freeze
    PRIOR_QUARTER_WARNING_CODES = %w[
      fuzzy_previous_quarter_match
      historical_category_coverage_incomplete
      historical_merchant_match
      historical_template_match
      single_historical_match
    ].freeze
    UNCERTAIN_WARNING_CODES = %w[
      historical_gst_suppressed
      mixed_or_unsafe_gst
    ].freeze
    UNCERTAIN_RULE_IDS = %w[uncertain_retailer mixed_retailer].freeze
    NO_GST_RULE_IDS = %w[
      ato_payment
      bank_fee
      bank_interest
      employee_wages
      explicit_loan_principal
      explicit_transfer
      superannuation
    ].freeze

    def initialize(codings:)
      @codings = codings
    end

    def call
      review_codings = @codings.to_a.select(&:review_required?)
      field_reasons_by_coding_id = {}
      row_reason_by_coding_id = {}
      grouped_codings = REASON_PRIORITY.index_with { [] }

      review_codings.each do |coding|
        field_reasons = field_reasons_for(coding)
        field_reasons_by_coding_id[coding.id] = field_reasons
        primary_reason = primary_reason_for(field_reasons)
        row_reason_by_coding_id[coding.id] = reason_payload(primary_reason)
        grouped_codings.fetch(primary_reason) << coding
      end

      {
        total_review_rows: review_codings.length,
        field_counts: {
          category: review_codings.count(&:category_review_required?),
          gst: review_codings.count(&:gst_review_required?)
        },
        field_combinations: field_combinations(review_codings),
        reason_groups: reason_groups(grouped_codings),
        row_reason_by_coding_id: row_reason_by_coding_id,
        field_reasons_by_coding_id: field_reasons_by_coding_id
      }
    end

    private

    def field_reasons_for(coding)
      reasons = {}
      reasons[:category] = category_reason(coding) if coding.category_review_required?
      reasons[:gst] = gst_reason(coding) if coding.gst_review_required?
      reasons
    end

    def category_reason(coding)
      if coding.category_source == "manual"
        field_reason(
          :other,
          "Manually edited Category reopened",
          "This Category was entered manually and its Reviewed check was later cleared. Confirm the manual value, then mark the row Reviewed again."
        )
      elsif uncertain_category?(coding)
        field_reason(
          :uncertain_or_blank,
          "Category intentionally left blank",
          "This retailer or description can represent different kinds of purchases, so the Category was left blank for a person to confirm."
        )
      elsif historical_evidence_conflict?(coding)
        field_reason(
          :historical_gst_issue,
          "Prior-quarter coding conflicts",
          "Different prior-quarter merchant or bank-template evidence points to conflicting coding, so the Category was left blank for confirmation."
        )
      elsif coding.category_source == "rule"
        field_reason(:rule_derived, "Category suggested by a rule", rule_detail(coding, field: :category))
      elsif prior_quarter_category_review?(coding)
        field_reason(
          :prior_quarter_non_exact,
          "Prior-quarter Category needs confirmation",
          prior_quarter_detail(coding, field: :category)
        )
      elsif coding.category_source == "unmatched" || coding.suggested_category.blank? || warning?(coding, "category_unclassified")
        field_reason(
          :unclassified,
          "No reliable Category match",
          "No reliable prior-quarter match or safe rule supplied a Category. Review the description and select the Category manually."
        )
      else
        field_reason(
          :other,
          "Category needs confirmation",
          "The Category suggestion did not meet the automatic acceptance checks and should be confirmed manually."
        )
      end
    end

    def gst_reason(coding)
      if coding.gst_source == "manual"
        field_reason(
          :other,
          "Manually edited GST reopened",
          "This GST value was entered manually and its Reviewed check was later cleared. Confirm the manual value, then mark the row Reviewed again."
        )
      elsif uncertain_gst?(coding)
        field_reason(
          :uncertain_or_blank,
          "GST intentionally left blank",
          "This supplier may include taxable and GST-free items. Check the current tax invoice before entering GST or confirming the blank value."
        )
      elsif historical_evidence_conflict?(coding)
        field_reason(
          :historical_gst_issue,
          "Prior-quarter coding conflicts",
          "Different prior-quarter merchant or bank-template evidence points to conflicting coding, so GST was left blank for confirmation."
        )
      elsif historical_gst_issue?(coding)
        field_reason(
          :historical_gst_issue,
          historical_gst_title(coding),
          historical_gst_detail(coding)
        )
      elsif coding.gst_source == "rule" || rule_review?(coding)
        field_reason(:rule_derived, "GST calculated by a rule", rule_detail(coding, field: :gst))
      elsif prior_quarter_gst_review?(coding)
        field_reason(
          :prior_quarter_non_exact,
          "Prior-quarter GST needs confirmation",
          prior_quarter_detail(coding, field: :gst)
        )
      elsif coding.gst_source == "unmatched" || warning?(coding, "gst_unclassified")
        field_reason(
          :unclassified,
          "No reliable GST treatment",
          "No reliable GST value was available. Check the current tax invoice, then enter GST or deliberately confirm a blank value."
        )
      else
        field_reason(
          :other,
          "GST needs confirmation",
          "The GST suggestion did not meet the automatic acceptance checks and should be confirmed manually."
        )
      end
    end

    def primary_reason_for(field_reasons)
      keys = field_reasons.values.map { |reason| reason.fetch(:key) }
      REASON_PRIORITY.find { |key| keys.include?(key) } || :other
    end

    def reason_groups(grouped_codings)
      REASON_PRIORITY.filter_map do |key|
        codings = grouped_codings.fetch(key)
        next if codings.empty?

        reason_payload(key).merge(
          count: codings.length,
          category_count: codings.count(&:category_review_required?),
          gst_count: codings.count(&:gst_review_required?),
          coding_ids: codings.map(&:id)
        )
      end
    end

    def reason_payload(key)
      REASON_DEFINITIONS.fetch(key).merge(key: key)
    end

    def field_reason(key, title, detail)
      { key: key, title: title, detail: detail }
    end

    def field_combinations(codings)
      {
        category_only: codings.count { |coding| coding.category_review_required? && !coding.gst_review_required? },
        gst_only: codings.count { |coding| !coding.category_review_required? && coding.gst_review_required? },
        both: codings.count { |coding| coding.category_review_required? && coding.gst_review_required? }
      }
    end

    def uncertain_category?(coding)
      metadata_value(coding, "category_preserved_as_manual") && coding.suggested_category.blank? ||
        metadata_value(coding, "category_suppressed_by_rule_id").in?(UNCERTAIN_RULE_IDS) ||
        warning?(coding, "historical_category_suppressed")
    end

    def uncertain_gst?(coding)
      metadata_value(coding, "gst_preserved_as_manual") && coding.suggested_gst_amount.nil? ||
        metadata_value(coding, "gst_suppressed_by_rule_id").in?(UNCERTAIN_RULE_IDS) ||
        rule_id(coding).in?(UNCERTAIN_RULE_IDS) ||
        warning_codes(coding).intersect?(UNCERTAIN_WARNING_CODES)
    end

    def historical_gst_issue?(coding)
      warning_codes(coding).intersect?(HISTORICAL_GST_WARNING_CODES) ||
        metadata_value(coding, "gst_consensus_status").in?(%w[incomplete conflict])
    end

    def historical_evidence_conflict?(coding)
      warning?(coding, "historical_evidence_conflict") || metadata_value(coding, "match_type") == "evidence_conflict"
    end

    def prior_quarter_category_review?(coding)
      coding.category_source == "previous_quarter_fuzzy" ||
        metadata_value(coding, "match_type").in?(%w[fuzzy merchant template]) ||
        warning_codes(coding).intersect?(PRIOR_QUARTER_WARNING_CODES) ||
        (coding.category_source == "previous_quarter_exact" && warning?(coding, "historical_category_coverage_incomplete"))
    end

    def prior_quarter_gst_review?(coding)
      coding.gst_source == "previous_quarter_fuzzy" ||
        coding.category_source == "previous_quarter_fuzzy" ||
        metadata_value(coding, "match_type").in?(%w[fuzzy merchant template]) ||
        warning_codes(coding).intersect?(PRIOR_QUARTER_WARNING_CODES)
    end

    def rule_review?(coding)
      return false if rule_id(coding) == "unmatched"

      coding.category_source == "rule" ||
        rule_id(coding).present? ||
        warning?(coding, "rule_suggestion_requires_review") ||
        warning?(coding, "tax_invoice_required")
    end

    def historical_gst_title(coding)
      warning?(coding, "historical_gst_conflict") || metadata_value(coding, "gst_consensus_status") == "conflict" ?
        "Prior-quarter GST is inconsistent" :
        "Prior-quarter GST is missing"
    end

    def historical_gst_detail(coding)
      if warning?(coding, "historical_gst_conflict") || metadata_value(coding, "gst_consensus_status") == "conflict"
        "Matching prior-quarter rows used conflicting GST treatments or proportions. Check the current tax invoice instead of inheriting one of them."
      else
        "Matching prior-quarter rows did not contain enough consistent GST information. Check the current tax invoice before confirming GST."
      end
    end

    def prior_quarter_detail(coding, field:)
      match_type = metadata_value(coding, "match_type").to_s
      noun = field == :category ? "Category" : "GST"
      case match_type
      when "merchant"
        "The merchant appeared in the prior quarter, but the transaction wording differs. Confirm the proposed #{noun}."
      when "template"
        "A recurring bank-description template matched, but its support, coded coverage or safety level is below automatic acceptance. Confirm the #{noun}."
      when "fuzzy"
        "A similar, not exact, prior-quarter description matched#{confidence_suffix(coding, field)}. Confirm the proposed #{noun}."
      when "exact"
        "The description matched exactly, but the coded prior-quarter coverage was incomplete. Confirm the proposed #{noun}."
      else
        "Prior-quarter evidence produced this #{noun}, but it did not meet the automatic acceptance checks. Confirm it manually."
      end
    end

    def rule_detail(coding, field:)
      noun = field == :category ? "Category" : "GST"
      rule_name = rule_id(coding).to_s.humanize.presence || "accounting"
      if rule_id(coding) == "paired_validation_offset"
        "An equal-and-opposite validation pair was detected. Confirm both transactions belong together and that the #{noun} should remain outside GST."
      elsif field == :gst && rule_id(coding).in?(NO_GST_RULE_IDS)
        "The #{rule_name} rule set GST to 0 because this transaction type normally has no claimable GST. Confirm the transaction type before accepting the no-GST treatment."
      elsif warning?(coding, "tax_invoice_required")
        "The #{rule_name} rule suggested this #{noun}. Verify the current tax invoice, supplier GST status and business-use percentage."
      else
        "The #{rule_name} rule suggested this #{noun}. Confirm the transaction's business purpose and supporting documents."
      end
    end

    def confidence_suffix(coding, field)
      confidence = field == :category ? coding.category_confidence : coding.gst_confidence
      confidence.present? ? " (#{confidence.to_f.round(1)}% confidence)" : ""
    end

    def rule_id(coding)
      metadata_value(coding, "rule_id") ||
        metadata_value(coding, "category_overridden_by_rule_id") ||
        metadata_value(coding, "gst_fallback_rule_id")
    end

    def metadata_value(coding, key)
      coding.metadata.to_h[key]
    end

    def warning?(coding, code)
      warning_codes(coding).include?(code)
    end

    def warning_codes(coding)
      coding.warning_codes.to_a.map(&:to_s)
    end
  end
end
