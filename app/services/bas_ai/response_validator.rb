module BasAi
  class ResponseValidator
    Result = Data.define(:valid?, :suggestions, :errors)

    REQUIRED_DATA_KEYS = {
      "invoice_extraction" => %w[
        document_type
        invoice_number
        issue_date
        supplier_or_customer_name
        abn_if_found
        total_amount
        gst_amount
        currency
        suggested_gst_code
        payment_method
        confidence
        missing_fields
        needs_review
        explanation
      ],
      "gst_code" => %w[
        source_type
        source_id
        suggested_gst_code
        confidence
        needs_review
        explanation
      ],
      "match" => %w[
        suggested_match_type
        source_ids
        matched_amount
        confidence
        explanation
        needs_review
      ],
      "query" => %w[
        query_type
        title
        details
        related_source_type
        related_source_id
        confidence
      ],
      "summary" => %w[
        summary
        unresolved_risks
        suggested_admin_actions
        confidence
      ]
    }.freeze

    def self.validate(response)
      new(response).validate
    end

    def initialize(response)
      @response = response
      @errors = []
      @validated_suggestions = []
    end

    def validate
      unless response.respond_to?(:suggestions)
        return Result.new(valid?: false, suggestions: [], errors: [ "Provider response is invalid." ])
      end

      Array(response.suggestions).each_with_index do |suggestion, index|
        validate_suggestion(suggestion, index)
      end

      Result.new(valid?: errors.blank?, suggestions: validated_suggestions, errors: errors)
    end

    private

    attr_reader :response, :errors, :validated_suggestions

    def validate_suggestion(suggestion, index)
      unless suggestion.is_a?(Hash)
        errors << "Suggestion #{index + 1} must be an object."
        return
      end

      type = suggestion["suggestion_type"].to_s
      unless BasAiSuggestion::SUGGESTION_TYPE_VALUES.include?(type)
        errors << "Suggestion #{index + 1} has unsupported type."
        return
      end

      data = suggestion["suggested_data"]
      unless data.is_a?(Hash)
        errors << "Suggestion #{index + 1} must include suggested_data."
        return
      end

      missing_keys = REQUIRED_DATA_KEYS.fetch(type) - data.keys.map(&:to_s)
      if missing_keys.any?
        errors << "Suggestion #{index + 1} missing required fields: #{missing_keys.join(', ')}."
        return
      end

      validated_suggestions << {
        "suggestion_type" => type,
        "source_type" => suggestion["source_type"].presence || data["source_type"] || data["related_source_type"],
        "source_id" => suggestion["source_id"].presence || data["source_id"] || data["related_source_id"],
        "confidence" => suggestion["confidence"].presence || data["confidence"],
        "explanation" => suggestion["explanation"].presence || data["explanation"],
        "suggested_data" => data.slice(*REQUIRED_DATA_KEYS.fetch(type))
      }
    end
  end
end
