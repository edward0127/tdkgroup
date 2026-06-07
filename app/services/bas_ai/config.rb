module BasAi
  class Config
    DEFAULT_MAX_OUTPUT_TOKENS = 2000
    OPENAI_WARNING_MESSAGE = "OpenAI AI suggestions send selected structured BAS job data to OpenAI. Do not use AI suggestions as final BAS figures. Accountant review is required.".freeze
    TRUE_VALUES = %w[true 1 yes on].freeze

    def self.current
      new
    end

    def enabled?
      TRUE_VALUES.include?(ENV.fetch("BAS_AI_ENABLED", "false").to_s.downcase)
    end

    def disabled?
      !enabled?
    end

    def provider
      ENV.fetch("BAS_AI_PROVIDER", "disabled").presence || "disabled"
    end

    def model_name
      ENV.fetch("BAS_AI_MODEL", "").to_s
    end

    def max_output_tokens
      value = ENV.fetch("BAS_AI_MAX_OUTPUT_TOKENS", DEFAULT_MAX_OUTPUT_TOKENS).to_i
      value.positive? ? value : DEFAULT_MAX_OUTPUT_TOKENS
    end

    def configured_provider?
      enabled? && provider != "disabled"
    end

    def openai_provider?
      provider == "openai"
    end

    def openai_ready?
      enabled? && openai_provider? && api_key_configured? && model_name.present?
    end

    def openai_warning_message
      OPENAI_WARNING_MESSAGE if enabled? && openai_provider?
    end

    def safe_configuration_message
      return "AI suggestions are not enabled." unless enabled?
      return "OpenAI BAS AI provider is not fully configured." if openai_provider? && !openai_ready?

      nil
    end

    def api_key_configured?
      ENV["BAS_AI_API_KEY"].present?
    end

    def public_settings
      {
        enabled: enabled?,
        provider: provider,
        model_name: model_name.presence,
        max_output_tokens: max_output_tokens,
        api_key_configured: api_key_configured?
      }
    end
  end
end
