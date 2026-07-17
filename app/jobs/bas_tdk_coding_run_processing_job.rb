class BasTdkCodingRunProcessingJob < ApplicationJob
  queue_as :default

  def perform(coding_run_id:, actor_username: "admin")
    coding_run = BasTdkCodingRun.find_by(id: coding_run_id)
    return if coding_run.blank? || coding_run.bas_job.blank? || !coding_run.bas_job.tdk_group_workflow?
    return unless claim_for_processing(coding_run, actor_username)

    create_audit_event(coding_run, "bas_tdk_coding_run_processing_started", actor_username)
    BasTdk::CodingRunProcessor.new(
      coding_run: coding_run,
      actor_username: actor_username
    ).call

    coding_run.reload
    create_audit_event(coding_run, terminal_event_type(coding_run), actor_username)
  rescue StandardError => e
    mark_failed_safely(coding_run_id, actor_username, e)
  end

  private

  def claim_for_processing(coding_run, actor_username)
    coding_run.with_lock do
      coding_run.reload
      return false unless coding_run.queued?

      coding_run.update!(
        status: "processing",
        processing_started_at: Time.current,
        processing_finished_at: nil,
        requested_by: coding_run.requested_by.presence || actor_username,
        row_errors: []
      )
      true
    end
  end

  def terminal_event_type(coding_run)
    case coding_run.status
    when "processed" then "bas_tdk_coding_run_processing_completed"
    when "needs_mapping" then "bas_tdk_coding_run_column_mapping_required"
    when "superseded" then "bas_tdk_coding_run_processing_superseded"
    else "bas_tdk_coding_run_processing_failed"
    end
  end

  def mark_failed_safely(coding_run_id, actor_username, exception)
    coding_run = BasTdkCodingRun.find_by(id: coding_run_id)
    return if coding_run.blank? || coding_run.terminal_status?

    coding_run.update!(
      status: "failed",
      processing_finished_at: Time.current,
      row_errors: [ "Category/GST coding could not be completed. Review the reference workbook and try again." ],
      metadata: coding_run.metadata.to_h.merge(
        "exception_class" => exception.class.name,
        "exception_message" => exception.message.to_s
      )
    )
    create_audit_event(coding_run, "bas_tdk_coding_run_processing_failed", actor_username)
  rescue StandardError
    nil
  end

  def create_audit_event(coding_run, event_type, actor_username)
    BasAuditEvent.create!(
      bas_job: coding_run.bas_job,
      auditable: coding_run,
      event_type: event_type,
      actor_username: actor_username,
      metadata: {
        bas_tdk_coding_run_id: coding_run.id,
        target_workbook_id: coding_run.target_workbook_id,
        status: coding_run.status,
        version_number: coding_run.version_number,
        ruleset_version: coding_run.ruleset_version,
        source_filename: coding_run.source_filename
      }
    )
  rescue ActiveRecord::RecordInvalid
    nil
  end
end
