module BasAi
  class ResponseValidator
    Result = Data.define(:valid?, :suggestions, :errors)

    INVALID_OPENAI_FORMAT_MESSAGE = "OpenAI returned an invalid suggestion format. No suggestions were applied. Please retry or contact support.".freeze
    INVALID_PROVIDER_FORMAT_MESSAGE = "AI provider returned an invalid suggestion format. No suggestions were applied. Please retry or contact support.".freeze
    OVERALL_STATUS_VALUES = %w[no_action_needed needs_admin_review].freeze

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

    COMMON_SUGGESTION_KEYS = %w[
      suggestion_type
      confidence
      explanation
      suggested_data
    ].freeze

    FIELD_SCHEMAS = {
      "abn_if_found" => { type: "string" },
      "confidence" => { type: "number" },
      "currency" => { type: "string" },
      "details" => { type: "string" },
      "document_type" => { type: "string" },
      "explanation" => { type: "string" },
      "gst_amount" => { type: "string" },
      "invoice_number" => { type: "string" },
      "issue_date" => { type: "string" },
      "matched_amount" => { type: "string" },
      "missing_fields" => { type: "array", items: { type: "string" } },
      "needs_review" => { type: "boolean" },
      "payment_method" => { type: "string" },
      "query_type" => { type: "string" },
      "related_source_id" => { type: [ "integer", "null" ] },
      "related_source_type" => { type: [ "string", "null" ] },
      "source_id" => { type: [ "integer", "null" ] },
      "source_ids" => {
        type: "object",
        additionalProperties: false,
        required: %w[invoice_ids bank_transaction_id cash_transaction_id],
        properties: {
          invoice_ids: { type: "array", items: { type: "integer" } },
          bank_transaction_id: { type: [ "integer", "null" ] },
          cash_transaction_id: { type: [ "integer", "null" ] }
        }
      },
      "source_type" => { type: [ "string", "null" ] },
      "suggested_admin_actions" => { type: "array", items: { type: "string" } },
      "suggested_gst_code" => { type: "string" },
      "suggested_match_type" => { type: "string" },
      "summary" => { type: "string" },
      "supplier_or_customer_name" => { type: "string" },
      "title" => { type: "string" },
      "total_amount" => { type: "string" },
      "unresolved_risks" => { type: "array", items: { type: "string" } }
    }.freeze

    def self.validate(response)
      new(response).validate
    end

    def self.openai_response_schema
      {
        type: "object",
        additionalProperties: false,
        required: %w[review_summary overall_status suggestions],
        properties: {
          review_summary: { type: "string" },
          overall_status: { type: "string", enum: OVERALL_STATUS_VALUES },
          suggestions: {
            type: "array",
            items: {
              anyOf: REQUIRED_DATA_KEYS.keys.map { |suggestion_type| openai_suggestion_schema(suggestion_type) }
            }
          }
        }
      }
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

    def self.openai_suggestion_schema(suggestion_type)
      {
        type: "object",
        additionalProperties: false,
        required: COMMON_SUGGESTION_KEYS + %w[source_type source_id],
        properties: {
          suggestion_type: { type: "string", enum: [ suggestion_type ] },
          source_type: { type: [ "string", "null" ] },
          source_id: { type: [ "integer", "null" ] },
          confidence: { type: "number" },
          explanation: { type: "string" },
          suggested_data: openai_suggested_data_schema(suggestion_type)
        }
      }
    end

    def self.openai_suggested_data_schema(suggestion_type)
      required_keys = REQUIRED_DATA_KEYS.fetch(suggestion_type)

      {
        type: "object",
        additionalProperties: false,
        required: required_keys,
        properties: required_keys.index_with { |key| FIELD_SCHEMAS.fetch(key) }
      }
    end
  end
end
