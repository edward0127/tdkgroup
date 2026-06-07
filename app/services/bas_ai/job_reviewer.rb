module BasAi
  class JobReviewer
    def initialize(run:, provider:, actor_username:)
      @run = run
      @provider = provider
      @actor_username = actor_username
    end

    def call
      response = provider.review_job(job_summary)
      validation = BasAi::ResponseValidator.validate(response)
      return failure_result(response.error_message.presence || validation.errors.to_sentence) unless response.ok? && validation.valid?

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

    def bas_job
      run.bas_job
    end

    def job_summary
      {
        "bas_job_id" => bas_job.id,
        "period_start" => bas_job.period_start&.to_fs(:db),
        "period_end" => bas_job.period_end&.to_fs(:db),
        "gst_basis" => bas_job.gst_basis,
        "reporting_method" => bas_job.reporting_method,
        "status" => bas_job.status,
        "open_query_count" => bas_job.queries.open_items.count,
        "proposed_match_count" => bas_job.matches.proposed.count,
        "unmatched_bank_transaction_count" => bas_job.bank_transactions.unmatched.count,
        "unmatched_invoice_count" => bas_job.invoices.unmatched.count,
        "invoices" => bas_job.invoices.limit(50).map do |invoice|
          {
            "id" => invoice.id,
            "direction" => invoice.direction,
            "issue_date" => invoice.issue_date&.to_fs(:db),
            "total_amount" => invoice.total_amount&.to_s("F"),
            "gst_amount" => invoice.gst_amount&.to_s("F"),
            "gst_code" => invoice.gst_code,
            "status" => invoice.status,
            "payment_method" => invoice.payment_method
          }
        end
      }
    end

    def failure_result(message)
      BasAi::Provider::Result.new(
        ok?: false,
        summary: nil,
        suggestions: [],
        error_message: message.presence || "AI response could not be validated."
      )
    end
  end
end
