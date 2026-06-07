require "json"
require "net/http"
require "uri"

module BasAi
  class OpenaiProvider < Provider
    ENDPOINT = URI("https://api.openai.com/v1/responses")
    SAFE_CONFIG_ERROR = "OpenAI BAS AI provider is not fully configured.".freeze
    DOCUMENT_TEXT_DISABLED_MESSAGE = "OpenAI document extraction is disabled until safe document text extraction is implemented.".freeze
    OPEN_TIMEOUT_SECONDS = 10
    READ_TIMEOUT_SECONDS = 60
    WRITE_TIMEOUT_SECONDS = 10

    def initialize(config: BasAi::Config.current, http_client: Net::HTTP)
      super(config: config)
      @http_client = http_client
    end

    def review_job(job_summary)
      return disabled_result unless openai_enabled?
      return missing_config_result unless configured?

      request_suggestions(
        input_kind: "job_review",
        summary: "Review this structured BAS job summary and suggest admin review items only.",
        structured_payload: job_summary
      )
    end

    def extract_document(document_summary)
      return disabled_result unless openai_enabled?
      return missing_config_result unless configured?

      Provider::Result.new(ok?: false, summary: nil, suggestions: [], error_message: DOCUMENT_TEXT_DISABLED_MESSAGE)
    end

    private

    attr_reader :http_client

    def openai_enabled?
      config.enabled? && config.provider == "openai"
    end

    def configured?
      api_key.present? && config.model_name.present?
    end

    def api_key
      ENV["BAS_AI_API_KEY"].to_s
    end

    def request_suggestions(input_kind:, summary:, structured_payload:)
      response = http_client.start(ENDPOINT.host, ENDPOINT.port, **http_start_options) do |http|
        configure_timeouts(http)
        http.request(build_request(input_kind: input_kind, summary: summary, structured_payload: structured_payload))
      end

      return api_error_result(response.code) unless response.code.to_i.between?(200, 299)

      parse_response(response.body)
    rescue JSON::ParserError
      Provider::Result.new(ok?: false, summary: nil, suggestions: [], error_message: "OpenAI response was not valid JSON.")
    rescue StandardError
      Provider::Result.new(ok?: false, summary: nil, suggestions: [], error_message: "OpenAI BAS AI request failed safely.")
    end

    def http_start_options
      {
        use_ssl: true,
        open_timeout: OPEN_TIMEOUT_SECONDS,
        read_timeout: READ_TIMEOUT_SECONDS
      }.tap do |options|
        options[:write_timeout] = WRITE_TIMEOUT_SECONDS if Net::HTTP.method_defined?(:write_timeout=)
      end
    end

    def configure_timeouts(http)
      http.open_timeout = OPEN_TIMEOUT_SECONDS if http.respond_to?(:open_timeout=)
      http.read_timeout = READ_TIMEOUT_SECONDS if http.respond_to?(:read_timeout=)
      http.write_timeout = WRITE_TIMEOUT_SECONDS if http.respond_to?(:write_timeout=)
    end

    def build_request(input_kind:, summary:, structured_payload:)
      request = Net::HTTP::Post.new(ENDPOINT)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(request_payload(input_kind: input_kind, summary: summary, structured_payload: structured_payload))
      request
    end

    def request_payload(input_kind:, summary:, structured_payload:)
      {
        model: config.model_name,
        store: false,
        max_output_tokens: config.max_output_tokens,
        input: [
          {
            role: "system",
            content: [
              {
                type: "input_text",
                text: system_prompt
              }
            ]
          },
          {
            role: "user",
            content: [
              {
                type: "input_text",
                text: JSON.generate(
                  {
                    input_kind: input_kind,
                    task: summary,
                    data: structured_payload
                  }
                )
              }
            ]
          }
        ],
        text: {
          format: {
            type: "json_schema",
            name: "bas_ai_suggestions",
            strict: false,
            schema: response_schema
          }
        }
      }
    end

    def system_prompt
      <<~PROMPT.squish
        You generate JSON only for admin-only BAS working paper suggestions.
        Suggest review actions only. Do not approve BAS figures, lodge BAS, lock jobs,
        override deterministic calculations, or treat suggestions as final.
        Use only the structured fields provided. Do not request or include raw document text.
      PROMPT
    end

    def response_schema
      {
        type: "object",
        additionalProperties: false,
        required: [ "summary", "suggestions" ],
        properties: {
          summary: { type: "string" },
          suggestions: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: true,
              required: [ "suggestion_type", "confidence", "explanation", "suggested_data" ],
              properties: {
                suggestion_type: { type: "string", enum: BasAiSuggestion::SUGGESTION_TYPE_VALUES },
                status: { type: "string" },
                confidence: { type: "number" },
                source_type: { type: [ "string", "null" ] },
                source_id: { type: [ "integer", "null" ] },
                explanation: { type: "string" },
                suggested_data: {
                  type: "object",
                  additionalProperties: true
                }
              }
            }
          }
        }
      }
    end

    def parse_response(body)
      parsed_body = JSON.parse(body)
      output_text = extract_output_text(parsed_body)
      return Provider::Result.new(ok?: false, summary: nil, suggestions: [], error_message: "OpenAI response did not include suggestion JSON.") if output_text.blank?

      suggestion_body = JSON.parse(output_text)
      Provider::Result.new(
        ok?: true,
        summary: suggestion_body["summary"],
        suggestions: Array(suggestion_body["suggestions"]),
        error_message: nil
      )
    rescue JSON::ParserError
      Provider::Result.new(ok?: false, summary: nil, suggestions: [], error_message: "OpenAI response was not valid JSON.")
    end

    def extract_output_text(parsed_body)
      return parsed_body["output_text"] if parsed_body["output_text"].present?

      Array(parsed_body["output"]).flat_map { |item| Array(item["content"]) }.find do |content|
        content["type"].in?(%w[output_text text])
      end&.fetch("text", nil)
    end

    def api_error_result(status_code)
      Provider::Result.new(ok?: false, summary: nil, suggestions: [], error_message: "OpenAI BAS AI request failed with status #{status_code}.")
    end

    def disabled_result
      Provider::Result.new(ok?: false, summary: nil, suggestions: [], error_message: "OpenAI BAS AI provider is disabled.")
    end

    def missing_config_result
      Provider::Result.new(ok?: false, summary: nil, suggestions: [], error_message: SAFE_CONFIG_ERROR)
    end
  end
end
