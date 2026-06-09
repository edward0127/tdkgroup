require "test_helper"

class BasAiTest < ActiveSupport::TestCase
  test "config is disabled by default" do
    with_modified_env("BAS_AI_ENABLED" => nil, "BAS_AI_PROVIDER" => nil, "BAS_AI_MODEL" => nil, "BAS_AI_API_KEY" => nil, "BAS_AI_MAX_OUTPUT_TOKENS" => nil) do
      config = BasAi::Config.current

      assert config.disabled?
      assert_equal "disabled", config.provider
      assert_equal "", config.model_name
      assert_equal 2000, config.max_output_tokens
      assert_not config.api_key_configured?
      assert_not config.ui_enabled?
    end
  end

  test "config UI gate is controlled separately from backend enablement" do
    with_modified_env("BAS_AI_ENABLED" => "true", "BAS_AI_UI_ENABLED" => "true", "BAS_AI_PROVIDER" => "stub") do
      config = BasAi::Config.current

      assert config.enabled?
      assert config.ui_enabled?
    end

    with_modified_env("BAS_AI_ENABLED" => "true", "BAS_AI_UI_ENABLED" => nil, "BAS_AI_PROVIDER" => "stub") do
      config = BasAi::Config.current

      assert config.enabled?
      assert_not config.ui_enabled?
    end
  end

  test "disabled provider returns safe disabled result" do
    result = BasAi::DisabledProvider.new.review_job({})

    assert_not result.ok?
    assert_equal [], result.suggestions
    assert_equal "AI suggestions are not enabled.", result.error_message
  end

  test "provider factory returns openai provider only when enabled provider key and model are configured" do
    with_modified_env("BAS_AI_ENABLED" => "true", "BAS_AI_PROVIDER" => "openai", "BAS_AI_MODEL" => "gpt-test", "BAS_AI_API_KEY" => "sk-test-secret") do
      assert_instance_of BasAi::OpenaiProvider, BasAi::ProviderFactory.build
    end

    with_modified_env("BAS_AI_ENABLED" => "true", "BAS_AI_PROVIDER" => "openai", "BAS_AI_MODEL" => "gpt-test", "BAS_AI_API_KEY" => nil) do
      assert_instance_of BasAi::DisabledProvider, BasAi::ProviderFactory.build
    end

    with_modified_env("BAS_AI_ENABLED" => "false", "BAS_AI_PROVIDER" => "openai", "BAS_AI_MODEL" => "gpt-test", "BAS_AI_API_KEY" => "sk-test-secret") do
      assert_instance_of BasAi::DisabledProvider, BasAi::ProviderFactory.build
    end
  end

  test "openai provider sends no request when disabled" do
    with_modified_env("BAS_AI_ENABLED" => "false", "BAS_AI_PROVIDER" => "openai", "BAS_AI_MODEL" => "gpt-test", "BAS_AI_API_KEY" => "sk-test-secret") do
      http = RaisingHttpClient.new
      result = BasAi::OpenaiProvider.new(http_client: http).review_job({})

      assert_not result.ok?
      assert_equal "OpenAI BAS AI provider is disabled.", result.error_message
      assert_not http.called
    end
  end

  test "openai provider missing api key fails safely" do
    with_modified_env("BAS_AI_ENABLED" => "true", "BAS_AI_PROVIDER" => "openai", "BAS_AI_MODEL" => "gpt-test", "BAS_AI_API_KEY" => nil) do
      result = BasAi::OpenaiProvider.new(http_client: RaisingHttpClient.new).review_job({})

      assert_not result.ok?
      assert_equal "OpenAI BAS AI provider is not fully configured.", result.error_message
    end
  end

  test "openai provider handles valid structured response" do
    payload = {
      "review_summary" => "Synthetic OpenAI review.",
      "overall_status" => "needs_admin_review",
      "suggestions" => [ query_payload(bas_job) ]
    }
    response = openai_response(JSON.generate(payload))
    http = FakeHttpClient.new(response)

    with_modified_env("BAS_AI_ENABLED" => "true", "BAS_AI_PROVIDER" => "openai", "BAS_AI_MODEL" => "gpt-test", "BAS_AI_API_KEY" => "sk-test-secret", "BAS_AI_MAX_OUTPUT_TOKENS" => "1234") do
      result = BasAi::OpenaiProvider.new(http_client: http).review_job({ "bas_job_id" => 1 })

      assert result.ok?
      assert_equal "Synthetic OpenAI review.", result.summary
      assert_equal 1, result.suggestions.size
      assert BasAi::ResponseValidator.validate(result).valid?
      assert_equal "Bearer sk-test-secret", http.authorization_header
      assert_not_includes http.request_body, "sk-test-secret"

      request_body = JSON.parse(http.request_body)
      assert_equal false, request_body.fetch("store")
      assert_equal 1234, request_body.fetch("max_output_tokens")
      assert_equal true, request_body.dig("text", "format", "strict")
      schema = request_body.dig("text", "format", "schema")
      assert_includes schema.fetch("required"), "review_summary"
      assert_includes schema.fetch("required"), "overall_status"
      assert_includes schema.fetch("required"), "suggestions"
      assert_equal 10, http.start_options.fetch(:open_timeout)
      assert_equal 60, http.start_options.fetch(:read_timeout)
      assert_equal 10, http.open_timeout
      assert_equal 60, http.read_timeout
      assert_equal 10, http.write_timeout
    end
  end

  test "openai provider handles no-suggestion structured response" do
    payload = {
      "review_summary" => "No admin action was identified.",
      "overall_status" => "no_action_needed",
      "suggestions" => []
    }
    response = openai_response(JSON.generate(payload))

    with_modified_env("BAS_AI_ENABLED" => "true", "BAS_AI_PROVIDER" => "openai", "BAS_AI_MODEL" => "gpt-test", "BAS_AI_API_KEY" => "sk-test-secret") do
      result = BasAi::OpenaiProvider.new(http_client: FakeHttpClient.new(response)).review_job({ "bas_job_id" => 1 })

      assert result.ok?
      assert_equal "No admin action was identified.", result.summary
      assert_equal [], result.suggestions
      assert BasAi::ResponseValidator.validate(result).valid?
    end
  end

  test "openai provider disables document extraction without sending request" do
    with_modified_env("BAS_AI_ENABLED" => "true", "BAS_AI_PROVIDER" => "openai", "BAS_AI_MODEL" => "gpt-test", "BAS_AI_API_KEY" => "sk-test-secret") do
      http = RaisingHttpClient.new
      result = BasAi::OpenaiProvider.new(http_client: http).extract_document({ "bas_document_id" => 1 })

      assert_not result.ok?
      assert_equal BasAi::OpenaiProvider::DOCUMENT_TEXT_DISABLED_MESSAGE, result.error_message
      assert_not http.called
    end
  end

  test "openai provider handles invalid json safely" do
    response = openai_response("{")

    with_modified_env("BAS_AI_ENABLED" => "true", "BAS_AI_PROVIDER" => "openai", "BAS_AI_MODEL" => "gpt-test", "BAS_AI_API_KEY" => "sk-test-secret") do
      result = BasAi::OpenaiProvider.new(http_client: FakeHttpClient.new(response)).review_job({})

      assert_not result.ok?
      assert_equal "OpenAI response was not valid JSON.", result.error_message
      assert_not_includes result.error_message, "sk-test-secret"
    end
  end

  test "openai provider handles api error safely" do
    response = FakeHttpResponse.new("500", JSON.generate({ "error" => { "message" => "secret should not leak" } }))

    with_modified_env("BAS_AI_ENABLED" => "true", "BAS_AI_PROVIDER" => "openai", "BAS_AI_MODEL" => "gpt-test", "BAS_AI_API_KEY" => "sk-test-secret") do
      result = BasAi::OpenaiProvider.new(http_client: FakeHttpClient.new(response)).review_job({})

      assert_not result.ok?
      assert_equal "OpenAI BAS AI request failed with status 500.", result.error_message
      assert_not_includes result.error_message, "sk-test-secret"
    end
  end

  test "stub provider returns schema valid suggestions" do
    provider = BasAi::StubProvider.new
    result = provider.review_job({
      "bas_job_id" => 1,
      "open_query_count" => 0,
      "unmatched_bank_transaction_count" => 1,
      "invoices" => []
    })

    assert result.ok?
    validation = BasAi::ResponseValidator.validate(result)
    assert validation.valid?, validation.errors.to_sentence
    assert validation.suggestions.any? { |suggestion| suggestion["suggestion_type"] == "summary" }
    assert validation.suggestions.any? { |suggestion| suggestion["suggestion_type"] == "query" }
  end

  test "readiness checker blocks job review before structured records exist" do
    readiness = BasAi::ReadinessChecker.new(bas_job: bas_job)

    assert_not readiness.ready?
    assert_includes readiness.blockers, "Import structured BAS records before running AI review."
  end

  test "readiness checker blocks unknown GST and reporting settings" do
    job = bas_job
    job.update!(gst_basis: "unknown", reporting_method: "unknown")
    BasBankTransaction.create!(
      bas_job: job,
      transaction_date: Date.new(2026, 1, 2),
      description: "Synthetic ready record",
      amount: BigDecimal("110.00"),
      status: "ignored"
    )

    readiness = BasAi::ReadinessChecker.new(bas_job: job)

    assert_not readiness.ready?
    assert_includes readiness.blockers, "GST basis is unknown."
    assert_includes readiness.blockers, "Reporting method is unknown."
  end

  test "readiness checker blocks proposed and needs-review matches" do
    job = bas_job
    BasBankTransaction.create!(
      bas_job: job,
      transaction_date: Date.new(2026, 1, 2),
      description: "Synthetic ready record",
      amount: BigDecimal("110.00"),
      status: "ignored"
    )
    BasMatch.create!(bas_job: job, match_type: "manual", status: "proposed", matched_amount: BigDecimal("110.00"))
    BasMatch.create!(bas_job: job, match_type: "manual", status: "needs_review", matched_amount: BigDecimal("55.00"))

    readiness = BasAi::ReadinessChecker.new(bas_job: job)

    assert_not readiness.ready?
    assert_includes readiness.blockers, "Review proposed match suggestions before running AI review."
    assert_includes readiness.blockers, "Resolve needs-review matches before running AI review."
  end

  test "readiness checker allows imported records with matching review complete" do
    job = bas_job
    BasBankTransaction.create!(
      bas_job: job,
      transaction_date: Date.new(2026, 1, 2),
      description: "Synthetic ready record",
      amount: BigDecimal("110.00"),
      status: "ignored"
    )

    readiness = BasAi::ReadinessChecker.new(bas_job: job)

    assert readiness.ready?
    assert_includes readiness.warnings, "No client/internal queries have been generated yet."
    assert_includes readiness.warnings, "No report snapshot exists yet."
  end

  test "response validator accepts valid invoice extraction json and rejects missing fields" do
    valid_response = BasAi::Provider::Result.new(
      ok?: true,
      summary: "Synthetic",
      suggestions: [ invoice_extraction_payload ],
      error_message: nil
    )
    valid_result = BasAi::ResponseValidator.validate(valid_response)
    assert valid_result.valid?, valid_result.errors.to_sentence

    invalid_payload = invoice_extraction_payload.deep_dup
    invalid_payload["suggested_data"].delete("total_amount")
    invalid_response = BasAi::Provider::Result.new(
      ok?: true,
      summary: "Synthetic",
      suggestions: [ invalid_payload ],
      error_message: nil
    )
    invalid_result = BasAi::ResponseValidator.validate(invalid_response)
    assert_not invalid_result.valid?
    assert invalid_result.errors.any? { |error| error.include?("missing required fields") }
  end

  test "suggestion builder creates suggestions without raw prompt metadata" do
    job = bas_job
    run = ai_run(job)
    validation = BasAi::ResponseValidator.validate(
      BasAi::Provider::Result.new(ok?: true, summary: "Synthetic", suggestions: [ invoice_extraction_payload ], error_message: nil)
    )

    assert_difference "BasAiSuggestion.count", 1 do
      assert_difference "BasAuditEvent.count", 1 do
        BasAi::SuggestionBuilder.new(
          run: run,
          validated_suggestions: validation.suggestions,
          actor_username: "phase5"
        ).call
      end
    end

    event = BasAuditEvent.last
    assert_equal "bas_ai_suggestion_created", event.event_type
    assert_not event.metadata.key?("raw_prompt")
    assert_not event.metadata.key?("raw_response")
  end

  test "suggestion applier accepts invoice extraction only after admin action" do
    job = bas_job
    suggestion = ai_suggestion(job, invoice_extraction_payload)

    assert_difference "BasInvoice.count", 1 do
      BasAi::SuggestionApplier.new(suggestion: suggestion, actor_username: "phase5").accept!
    end

    invoice = BasInvoice.last
    assert_equal "purchase", invoice.direction
    assert_equal "needs_review", invoice.status
    assert_equal "taxable", invoice.gst_code
    assert_equal "accepted", suggestion.reload.status
    assert_equal "phase5", suggestion.accepted_by
  end

  test "suggestion applier accepts GST code suggestion and creates audit event" do
    job = bas_job
    invoice = BasInvoice.create!(
      bas_job: job,
      direction: "purchase",
      issue_date: Date.new(2026, 1, 1),
      party_name: "Synthetic Supplier",
      total_amount: BigDecimal("110.00"),
      gst_code: "unknown",
      status: "imported"
    )
    suggestion = ai_suggestion(job, gst_code_payload(invoice))

    assert_difference "BasAuditEvent.count", 1 do
      BasAi::SuggestionApplier.new(suggestion: suggestion, actor_username: "phase5").accept!
    end

    assert_equal "taxable", invoice.reload.gst_code
    assert_equal "accepted", suggestion.reload.status
    assert_equal "bas_ai_suggestion_accepted", BasAuditEvent.last.event_type
  end

  test "suggestion applier accepts query suggestion and creates BAS query" do
    job = bas_job
    suggestion = ai_suggestion(job, query_payload(job))

    assert_difference "BasQuery.count", 1 do
      BasAi::SuggestionApplier.new(suggestion: suggestion, actor_username: "phase5").accept!
    end

    query = BasQuery.last
    assert_equal "unmatched_bank_transaction", query.query_type
    assert query.auto_generated?
    assert_equal "accepted", suggestion.reload.status
  end

  test "rejecting suggestion does not change BAS data" do
    job = bas_job
    suggestion = ai_suggestion(job, invoice_extraction_payload)

    assert_no_difference "BasInvoice.count" do
      BasAi::SuggestionApplier.new(suggestion: suggestion, actor_username: "phase5").reject!
    end

    assert_equal "rejected", suggestion.reload.status
    assert_equal "phase5", suggestion.rejected_by
  end

  test "AI suggestion cannot approve lock or mutate final report snapshot totals" do
    job = bas_job
    snapshot = BasReportSnapshot.create!(
      bas_job: job,
      status: "final",
      totals: { "summary" => { "g1_total_sales" => "110.00" } },
      validation_errors: [],
      generated_at: Time.current,
      generated_by: "phase5",
      approved_at: Time.current,
      approved_by: "phase5"
    )
    suggestion = ai_suggestion(job, query_payload(job))

    BasAi::SuggestionApplier.new(suggestion: suggestion, actor_username: "phase5").accept!

    assert_not_equal "approved", job.reload.status
    assert_not_equal "locked", job.status
    assert_equal({ "summary" => { "g1_total_sales" => "110.00" } }, snapshot.reload.totals)
  end

  test "locked job blocks AI suggestion apply" do
    job = bas_job
    suggestion = ai_suggestion(job, query_payload(job))
    job.update!(status: "locked", locked_at: Time.current, locked_by: "phase5")

    assert_raises(BasAi::SuggestionApplier::LockedJobError) do
      BasAi::SuggestionApplier.new(suggestion: suggestion, actor_username: "phase5").accept!
    end
  end

  test "marking needs review creates safe query and audit metadata" do
    job = bas_job
    suggestion = ai_suggestion(job, query_payload(job))

    assert_difference "BasQuery.count", 1 do
      BasAi::SuggestionApplier.new(suggestion: suggestion, actor_username: "phase5").mark_needs_review!
    end

    assert_equal "needs_review", suggestion.reload.status
    assert_equal "bas_ai_suggestion_needs_review", BasAuditEvent.last.event_type
    assert_not BasAuditEvent.last.metadata.key?("raw_prompt")
    assert_not BasAuditEvent.last.metadata.key?("document_text")
  end

  private

  def bas_job
    BasJob.create!(
      bas_client: BasClient.create!(legal_name: "Synthetic AI Client Pty Ltd"),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      gst_basis: "accrual",
      reporting_method: "simpler_bas"
    )
  end

  def ai_run(job)
    BasAiExtractionRun.create!(
      bas_job: job,
      status: "completed",
      provider: "stub",
      ai_model_name: "synthetic-model",
      input_kind: "job_review"
    )
  end

  def ai_suggestion(job, payload)
    validation = BasAi::ResponseValidator.validate(
      BasAi::Provider::Result.new(ok?: true, summary: "Synthetic", suggestions: [ payload ], error_message: nil)
    )
    attributes = validation.suggestions.first
    BasAiSuggestion.create!(
      bas_job: job,
      bas_ai_extraction_run: ai_run(job),
      suggestion_type: attributes.fetch("suggestion_type"),
      status: "proposed",
      confidence: attributes["confidence"],
      source_type: attributes["source_type"],
      source_id: attributes["source_id"],
      suggested_data: attributes.fetch("suggested_data"),
      explanation: attributes["explanation"]
    )
  end

  def invoice_extraction_payload
    {
      "suggestion_type" => "invoice_extraction",
      "source_type" => "BasDocument",
      "source_id" => 123,
      "confidence" => 82,
      "explanation" => "Synthetic invoice extraction.",
      "suggested_data" => {
        "document_type" => "supplier_invoice",
        "invoice_number" => "AI-001",
        "issue_date" => "2026-01-15",
        "supplier_or_customer_name" => "Synthetic Supplier",
        "abn_if_found" => "",
        "total_amount" => "110.00",
        "gst_amount" => "10.00",
        "currency" => "AUD",
        "suggested_gst_code" => "taxable",
        "payment_method" => "unknown",
        "confidence" => 82,
        "missing_fields" => [],
        "needs_review" => true,
        "explanation" => "Synthetic invoice extraction requires review."
      }
    }
  end

  def gst_code_payload(invoice)
    {
      "suggestion_type" => "gst_code",
      "source_type" => "BasInvoice",
      "source_id" => invoice.id,
      "confidence" => 90,
      "explanation" => "Synthetic GST suggestion.",
      "suggested_data" => {
        "source_type" => "BasInvoice",
        "source_id" => invoice.id,
        "suggested_gst_code" => "taxable",
        "confidence" => 90,
        "needs_review" => false,
        "explanation" => "Synthetic GST suggestion."
      }
    }
  end

  def query_payload(job)
    {
      "suggestion_type" => "query",
      "confidence" => 70,
      "explanation" => "Synthetic query suggestion.",
      "suggested_data" => {
        "query_type" => "unmatched_bank_transaction",
        "title" => "Synthetic AI query",
        "details" => "Synthetic AI query details.",
        "related_source_type" => "BasJob",
        "related_source_id" => job.id,
        "confidence" => 70
      }
    }
  end

  def openai_response(output_text)
    FakeHttpResponse.new(
      "200",
      JSON.generate(
        {
          "output" => [
            {
              "content" => [
                {
                  "type" => "output_text",
                  "text" => output_text
                }
              ]
            }
          ]
        }
      )
    )
  end

  class FakeHttpResponse
    attr_reader :code, :body

    def initialize(code, body)
      @code = code
      @body = body
    end
  end

  class FakeHttpClient
    attr_accessor :open_timeout, :read_timeout, :write_timeout
    attr_reader :request_body, :authorization_header, :start_options

    def initialize(response)
      @response = response
    end

    def start(_host, _port, **options)
      use_ssl = options.fetch(:use_ssl)
      raise "OpenAI requests must use SSL" unless use_ssl

      @start_options = options
      yield self
    end

    def request(request)
      @request_body = request.body
      @authorization_header = request["Authorization"]
      @response
    end
  end

  class RaisingHttpClient
    attr_reader :called

    def initialize
      @called = false
    end

    def start(*)
      @called = true
      raise "external request should not happen"
    end
  end
end
