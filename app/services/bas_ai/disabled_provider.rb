module BasAi
  class DisabledProvider < Provider
    DEFAULT_MESSAGE = "AI suggestions are not enabled.".freeze

    def initialize(config: BasAi::Config.current, message: DEFAULT_MESSAGE)
      super(config: config)
      @message = message
    end

    def review_job(_job_summary)
      disabled_result
    end

    def extract_document(_document_summary)
      disabled_result
    end

    private

    attr_reader :message

    def disabled_result
      Result.new(
        ok?: false,
        summary: message,
        suggestions: [],
        error_message: message
      )
    end
  end
end
