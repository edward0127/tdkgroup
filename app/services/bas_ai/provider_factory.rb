module BasAi
  class ProviderFactory
    def self.build(config: BasAi::Config.current)
      new(config: config).build
    end

    def initialize(config:)
      @config = config
    end

    def build
      return BasAi::DisabledProvider.new(config: config) unless config.enabled?

      case config.provider
      when "stub"
        BasAi::StubProvider.new(config: config)
      when "openai"
        if config.openai_ready?
          BasAi::OpenaiProvider.new(config: config)
        else
          BasAi::DisabledProvider.new(
            config: config,
            message: "OpenAI BAS AI provider is not fully configured."
          )
        end
      else
        BasAi::DisabledProvider.new(config: config)
      end
    end

    private

    attr_reader :config
  end
end
