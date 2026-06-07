module BasAi
  class Provider
    Result = Data.define(:ok?, :summary, :suggestions, :error_message)

    def initialize(config: BasAi::Config.current)
      @config = config
    end

    def review_job(_job_summary)
      raise NotImplementedError, "#{self.class.name} must implement #review_job"
    end

    def extract_document(_document_summary)
      raise NotImplementedError, "#{self.class.name} must implement #extract_document"
    end

    private

    attr_reader :config
  end
end
