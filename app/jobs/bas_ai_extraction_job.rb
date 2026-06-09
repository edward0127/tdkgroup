class BasAiExtractionJob < ApplicationJob
  queue_as :default

  def perform(bas_job_id:, bas_document_id: nil, input_kind: "job_review", actor_username: "admin")
    bas_job = BasJob.find(bas_job_id)
    input_kind = normalized_input_kind(input_kind)
    bas_document = document_input_kind?(input_kind) && bas_document_id.present? ? bas_job.documents.find(bas_document_id) : nil
    config = BasAi::Config.current
    provider = BasAi::ProviderFactory.build(config: config)
    run = create_run!(bas_job, bas_document, input_kind, config)

    start_run!(run, actor_username)
    result = reviewer_for(run, provider, input_kind, actor_username).call

    if result.ok?
      complete_run!(run, result.summary, actor_username)
    else
      fail_run!(run, result.error_message, actor_username)
    end

    run
  rescue ActiveRecord::RecordNotFound
    nil
  end

  private

  def create_run!(bas_job, bas_document, input_kind, config)
    bas_job.ai_extraction_runs.create!(
      bas_document: bas_document,
      status: "pending",
      provider: config.provider,
      ai_model_name: config.model_name,
      input_kind: input_kind,
      metadata: {
        bas_document_id: document_input_kind?(input_kind) ? bas_document&.id : nil,
        input_kind: input_kind
      }.compact
    )
  end

  def start_run!(run, actor_username)
    run.update!(status: "running", started_at: Time.current)
    create_audit_event(run, "bas_ai_run_started", actor_username)
  end

  def complete_run!(run, summary, actor_username)
    run.update!(
      status: "completed",
      completed_at: Time.current,
      summary: summary
    )
    create_audit_event(run, "bas_ai_run_completed", actor_username)
  end

  def fail_run!(run, error_message, actor_username)
    run.update!(
      status: "failed",
      completed_at: Time.current,
      error_message: error_message.presence || "AI run failed safely."
    )
    create_audit_event(run, "bas_ai_run_failed", actor_username)
  end

  def reviewer_for(run, provider, input_kind, actor_username)
    if input_kind == "document_text"
      BasAi::DocumentExtractor.new(run: run, provider: provider, actor_username: actor_username)
    else
      BasAi::JobReviewer.new(run: run, provider: provider, actor_username: actor_username)
    end
  end

  def normalized_input_kind(input_kind)
    input_kind.presence || "job_review"
  end

  def document_input_kind?(input_kind)
    input_kind.in?(BasAiExtractionRun::DOCUMENT_INPUT_KIND_VALUES)
  end

  def create_audit_event(run, event_type, actor_username)
    BasAuditEvent.create!(
      bas_job: run.bas_job,
      auditable: run,
      event_type: event_type,
      actor_username: actor_username,
      metadata: {
        bas_ai_extraction_run_id: run.id,
        status: run.status,
        provider: run.provider,
        model_name: run.ai_model_name,
        input_kind: run.input_kind,
        bas_document_id: run.bas_document_id
      }.compact
    )
  end
end
