require "test_helper"

class BasAiExtractionJobTest < ActiveJob::TestCase
  test "disabled config creates failed run safely" do
    job = bas_job

    with_modified_env("BAS_AI_ENABLED" => "false", "BAS_AI_PROVIDER" => "disabled") do
      assert_difference "BasAiExtractionRun.count", 1 do
        assert_no_difference "BasAiSuggestion.count" do
          BasAiExtractionJob.perform_now(bas_job_id: job.id, actor_username: "phase5")
        end
      end
    end

    run = BasAiExtractionRun.last
    assert_equal "failed", run.status
    assert_equal "AI suggestions are not enabled.", run.error_message
    assert_equal "bas_ai_run_failed", BasAuditEvent.last.event_type
  end

  test "openai config without api key creates failed run safely without secret metadata" do
    job = bas_job

    with_modified_env("BAS_AI_ENABLED" => "true", "BAS_AI_PROVIDER" => "openai", "BAS_AI_MODEL" => "gpt-test", "BAS_AI_API_KEY" => nil) do
      assert_difference "BasAiExtractionRun.count", 1 do
        assert_no_difference "BasAiSuggestion.count" do
          BasAiExtractionJob.perform_now(bas_job_id: job.id, actor_username: "phase5b")
        end
      end
    end

    run = BasAiExtractionRun.last
    assert_equal "failed", run.status
    assert_equal "OpenAI BAS AI provider is not fully configured.", run.error_message
    assert_equal "openai", run.provider
    assert_not BasAuditEvent.last.metadata.key?("api_key")
    assert_not BasAuditEvent.last.metadata.values.join.include?("sk-")
  end

  test "stub provider creates suggestions" do
    job = bas_job
    BasBankTransaction.create!(
      bas_job: job,
      transaction_date: Date.new(2026, 1, 2),
      description: "Synthetic unmatched",
      amount: BigDecimal("110.00")
    )

    with_modified_env("BAS_AI_ENABLED" => "true", "BAS_AI_PROVIDER" => "stub", "BAS_AI_MODEL" => "synthetic-model") do
      assert_difference "BasAiExtractionRun.count", 1 do
        assert_difference "BasAiSuggestion.count", 2 do
          BasAiExtractionJob.perform_now(bas_job_id: job.id, input_kind: "job_review", actor_username: "phase5")
        end
      end
    end

    run = BasAiExtractionRun.last
    assert_equal "completed", run.status
    assert_equal "stub", run.provider
    assert_equal "synthetic-model", run.ai_model_name
    assert_equal "bas_ai_run_completed", BasAuditEvent.last.event_type
  end

  test "stub provider creates document extraction suggestion" do
    job = bas_job
    document = bas_document(job)

    with_modified_env("BAS_AI_ENABLED" => "true", "BAS_AI_PROVIDER" => "stub") do
      assert_difference "BasAiSuggestion.where(suggestion_type: 'invoice_extraction').count", 1 do
        BasAiExtractionJob.perform_now(
          bas_job_id: job.id,
          bas_document_id: document.id,
          input_kind: "document_text",
          actor_username: "phase5"
        )
      end
    end

    assert_equal "completed", BasAiExtractionRun.last.status
  end

  test "openai document extraction fails safely without suggestions or invoices" do
    job = bas_job
    document = bas_document(job)

    with_modified_env("BAS_AI_ENABLED" => "true", "BAS_AI_PROVIDER" => "openai", "BAS_AI_MODEL" => "gpt-test", "BAS_AI_API_KEY" => "sk-test-secret") do
      assert_difference "BasAiExtractionRun.count", 1 do
        assert_no_difference "BasAiSuggestion.count" do
          assert_no_difference "BasInvoice.count" do
            BasAiExtractionJob.perform_now(
              bas_job_id: job.id,
              bas_document_id: document.id,
              input_kind: "document_text",
              actor_username: "phase6b"
            )
          end
        end
      end
    end

    run = BasAiExtractionRun.last
    assert_equal "failed", run.status
    assert_equal "openai", run.provider
    assert_equal "document_text", run.input_kind
    assert_equal BasAi::OpenaiProvider::DOCUMENT_TEXT_DISABLED_MESSAGE, run.error_message
  end

  test "invalid provider response fails safely" do
    job = bas_job
    run = BasAiExtractionRun.create!(bas_job: job, status: "running", input_kind: "job_review", provider: "stub")
    provider = Class.new(BasAi::Provider) do
      def review_job(_summary)
        BasAi::Provider::Result.new(ok?: true, summary: "Invalid", suggestions: [ { "suggestion_type" => "summary", "suggested_data" => {} } ], error_message: nil)
      end
    end.new

    result = BasAi::JobReviewer.new(run: run, provider: provider, actor_username: "phase5").call

    assert_not result.ok?
    assert_includes result.error_message, "missing required fields"
  end

  private

  def bas_job
    BasJob.create!(
      bas_client: BasClient.create!(legal_name: "Synthetic AI Job Client Pty Ltd"),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      gst_basis: "accrual",
      reporting_method: "simpler_bas"
    )
  end

  def bas_document(job)
    document = job.documents.build(title: "Synthetic AI document", document_type: "supplier_invoice")
    document.file.attach(
      io: StringIO.new("Date,Description,Amount\n01/01/2026,Synthetic,1.00\n"),
      filename: "synthetic-ai.csv",
      content_type: "text/csv"
    )
    document.save!
    document
  end
end
