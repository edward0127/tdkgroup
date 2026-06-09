module BasAi
  class DocumentExtractor
    UNSUPPORTED_TEXT_EXTRACTION_TYPES = %w[application/pdf image/jpeg image/png image/webp].freeze

    def initialize(run:, provider:, actor_username:)
      @run = run
      @provider = provider
      @actor_username = actor_username
    end

    def call
      return failure_result("Select a BAS document before running document extraction.") if run.bas_document.blank?
      return failure_result(BasAi::OpenaiProvider::DOCUMENT_TEXT_DISABLED_MESSAGE) if provider.is_a?(BasAi::OpenaiProvider)

      if unsupported_text_extraction? && !provider.is_a?(BasAi::StubProvider)
        return failure_result("Document text extraction for PDF/image files is not available in this phase.")
      end

      response = provider.extract_document(document_summary)
      return failure_result(response.error_message) unless response.ok?

      validation = BasAi::ResponseValidator.validate(response)
      unless validation.valid?
        record_validation_errors(validation.errors)
        return failure_result(invalid_format_message)
      end

      suggestions = BasAi::SuggestionBuilder.new(
        run: run,
        validated_suggestions: validation.suggestions,
        actor_username: actor_username
      ).call

      BasAi::Provider::Result.new(
        ok?: true,
        summary: response.summary,
        suggestions: suggestions,
        error_message: nil
      )
    end

    private

    attr_reader :run, :provider, :actor_username

    def document_summary
      document = run.bas_document
      {
        "bas_job_id" => run.bas_job_id,
        "bas_document_id" => document.id,
        "document_type" => document.document_type,
        "title" => document.title,
        "filename_extension" => File.extname(document.safe_filename).delete_prefix(".").downcase,
        "content_type" => document.file.attached? ? document.file.blob.content_type : nil,
        "period_start" => run.bas_job.period_start&.to_fs(:db),
        "period_end" => run.bas_job.period_end&.to_fs(:db)
      }
    end

    def unsupported_text_extraction?
      document = run.bas_document
      return false unless document&.file&.attached?

      UNSUPPORTED_TEXT_EXTRACTION_TYPES.include?(document.file.blob.content_type.to_s)
    end

    def failure_result(message)
      BasAi::Provider::Result.new(
        ok?: false,
        summary: nil,
        suggestions: [],
        error_message: message
      )
    end

    def invalid_format_message
      run.provider == "openai" ? BasAi::ResponseValidator::INVALID_OPENAI_FORMAT_MESSAGE : BasAi::ResponseValidator::INVALID_PROVIDER_FORMAT_MESSAGE
    end

    def record_validation_errors(validation_errors)
      run.update!(
        metadata: run.metadata.merge(
          "validation_error_type" => "invalid_suggestion_format",
          "validation_errors" => Array(validation_errors)
        )
      )
    end
  end
end
