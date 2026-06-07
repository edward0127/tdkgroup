require "test_helper"

class AdminBasAiControllerTest < ActionDispatch::IntegrationTest
  setup do
    login_as_admin
  end

  test "non-admin cannot access AI run or suggestion pages" do
    job = bas_job
    suggestion = ai_suggestion(job)

    reset!

    get admin_bas_job_ai_runs_path(job)
    assert_redirected_to admin_login_path

    get admin_bas_job_ai_suggestion_path(job, suggestion)
    assert_redirected_to admin_login_path

    post accept_admin_bas_job_ai_suggestion_path(job, suggestion)
    assert_redirected_to admin_login_path
  end

  test "admin can view AI disabled state" do
    job = bas_job

    with_modified_env("BAS_AI_ENABLED" => "false", "BAS_AI_PROVIDER" => "disabled") do
      get admin_bas_job_ai_runs_path(job)
    end

    assert_response :success
    assert_select "p", text: "AI suggestions are not enabled."
  end

  test "openai AI screens show warning and disable document extraction option" do
    job = bas_job
    warning = BasAi::Config::OPENAI_WARNING_MESSAGE

    with_modified_env("BAS_AI_ENABLED" => "true", "BAS_AI_PROVIDER" => "openai", "BAS_AI_MODEL" => "gpt-test", "BAS_AI_API_KEY" => "sk-test-secret") do
      get admin_bas_job_ai_runs_path(job)
      assert_response :success
      assert_select "p", text: warning
      assert_select "p", text: BasAi::OpenaiProvider::DOCUMENT_TEXT_DISABLED_MESSAGE
      assert_select "option[value=?]", "document_text", count: 0
      assert_no_match "sk-test-secret", response.body

      get admin_bas_job_ai_suggestions_path(job)
      assert_response :success
      assert_select "p", text: warning
      assert_no_match "sk-test-secret", response.body
    end
  end

  test "admin can trigger AI run with stub provider and view run details" do
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
          post admin_bas_job_ai_runs_path(job), params: {
            bas_ai_extraction_run: { input_kind: "job_review" }
          }
        end
      end
    end

    run = BasAiExtractionRun.last
    assert_redirected_to admin_bas_job_ai_run_path(job, run)
    assert_equal "completed", run.status
    assert_equal "phase5-admin", BasAuditEvent.last.actor_username

    get admin_bas_job_ai_run_path(job, run)
    assert_response :success
    assert_select "h1", "Job review"
  end

  test "admin can view suggestions and accept suggestion" do
    job = bas_job
    suggestion = ai_suggestion(job, suggestion_type: "query")

    get admin_bas_job_ai_suggestions_path(job)
    assert_response :success
    assert_select "td", "Query"

    assert_difference "BasQuery.count", 1 do
      post accept_admin_bas_job_ai_suggestion_path(job, suggestion)
    end

    assert_redirected_to admin_bas_job_ai_suggestion_path(job, suggestion)
    assert_equal "accepted", suggestion.reload.status
    assert_equal "bas_ai_suggestion_accepted", BasAuditEvent.last.event_type
    assert_equal "phase5-admin", BasAuditEvent.last.actor_username
  end

  test "admin can reject and mark suggestion needs review" do
    job = bas_job
    rejected_suggestion = ai_suggestion(job, suggestion_type: "summary")
    review_suggestion = ai_suggestion(job, suggestion_type: "summary")

    post reject_admin_bas_job_ai_suggestion_path(job, rejected_suggestion)

    assert_redirected_to admin_bas_job_ai_suggestion_path(job, rejected_suggestion)
    assert_equal "rejected", rejected_suggestion.reload.status
    assert_equal "bas_ai_suggestion_rejected", BasAuditEvent.last.event_type

    assert_difference "BasQuery.count", 1 do
      post mark_needs_review_admin_bas_job_ai_suggestion_path(job, review_suggestion)
    end

    assert_redirected_to admin_bas_job_ai_suggestion_path(job, review_suggestion)
    assert_equal "needs_review", review_suggestion.reload.status
    assert_equal "bas_ai_suggestion_needs_review", BasAuditEvent.last.event_type
  end

  test "locked job blocks AI run and suggestion actions" do
    job = bas_job(status: "locked", locked_at: Time.current, locked_by: "phase5-admin")
    suggestion = ai_suggestion(job, suggestion_type: "summary")

    assert_no_difference "BasAiExtractionRun.count" do
      post admin_bas_job_ai_runs_path(job), params: {
        bas_ai_extraction_run: { input_kind: "job_review" }
      }
    end
    assert_redirected_to admin_bas_job_ai_runs_path(job)

    assert_no_changes -> { suggestion.reload.status } do
      post accept_admin_bas_job_ai_suggestion_path(job, suggestion)
    end
    assert_redirected_to admin_bas_job_ai_suggestion_path(job, suggestion)
  end

  private

  def login_as_admin
    with_modified_env("ADMIN_USERNAME" => "phase5-admin", "ADMIN_PASSWORD" => "secret-password") do
      post admin_login_path, params: { username: "phase5-admin", password: "secret-password" }
      assert_redirected_to admin_root_path
    end
  end

  def bas_job(attributes = {})
    BasJob.create!({
      bas_client: BasClient.create!(legal_name: "Synthetic AI Controller Client Pty Ltd"),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      gst_basis: "accrual",
      reporting_method: "simpler_bas"
    }.merge(attributes))
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

  def ai_suggestion(job, suggestion_type: "summary")
    data = if suggestion_type == "query"
      {
        "query_type" => "unmatched_bank_transaction",
        "title" => "Synthetic AI query",
        "details" => "Synthetic AI query details.",
        "related_source_type" => "BasJob",
        "related_source_id" => job.id,
        "confidence" => 70
      }
    else
      {
        "summary" => "Synthetic AI summary",
        "unresolved_risks" => [],
        "suggested_admin_actions" => [ "Review synthetic items." ],
        "confidence" => 75
      }
    end

    BasAiSuggestion.create!(
      bas_job: job,
      bas_ai_extraction_run: ai_run(job),
      suggestion_type: suggestion_type,
      status: "proposed",
      confidence: BigDecimal("75"),
      suggested_data: data,
      explanation: "Synthetic AI suggestion."
    )
  end
end
