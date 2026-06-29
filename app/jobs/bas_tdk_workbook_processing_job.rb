class BasTdkWorkbookProcessingJob < ApplicationJob
  queue_as :default

  def perform(workbook_id:, actor_username: "admin")
    workbook = BasTdkWorkbook.find_by(id: workbook_id)
    return if workbook.blank? || workbook.bas_job.blank? || !workbook.bas_job.tdk_group_workflow?

    return unless claim_workbook_for_processing(workbook, actor_username)

    create_audit_event(workbook, "bas_tdk_workbook_processing_started", actor_username)

    workbook.source_file.open(tmpdir: Rails.root.join("tmp").to_s) do |file|
      BasTdk::WorkbookProcessor.new(
        bas_job: workbook.bas_job,
        workbook: workbook,
        source_path: file.path,
        actor_username: actor_username
      ).call
    end

    workbook.reload
    if workbook.processed?
      create_audit_event(workbook, "bas_tdk_workbook_processing_completed", actor_username)
    else
      create_audit_event(workbook, "bas_tdk_workbook_processing_failed", actor_username)
    end
  rescue StandardError => e
    mark_failed_safely(workbook_id, actor_username, e)
  end

  private

  def claim_workbook_for_processing(workbook, actor_username)
    workbook.with_lock do
      workbook.reload
      return false unless workbook.queued?

      unless workbook.source_file.attached?
        workbook.update!(
          status: "failed",
          row_errors: [ "Uploaded bank statement file is no longer attached. Please upload it again." ],
          processing_finished_at: Time.current,
          processed_at: Time.current
        )
        return false
      end

      workbook.update!(
        status: "processing",
        processing_started_at: Time.current,
        processing_finished_at: nil,
        processed_by: actor_username
      )
      true
    end
  end

  def mark_failed_safely(workbook_id, actor_username, exception)
    workbook = BasTdkWorkbook.find_by(id: workbook_id)
    return if workbook.blank?

    workbook.update!(
      status: "failed",
      row_count: 0,
      row_errors: [ "Bank statement file could not be read. Please upload a valid Excel, CSV or bank statement PDF." ],
      processing_finished_at: Time.current,
      processed_at: Time.current,
      metadata: workbook.metadata.merge(
        "exception_class" => exception.class.name,
        "exception_message" => exception.message.to_s
      )
    )
    create_audit_event(workbook, "bas_tdk_workbook_processing_failed", actor_username)
  rescue StandardError
    nil
  end

  def create_audit_event(workbook, event_type, actor_username)
    BasAuditEvent.create!(
      bas_job: workbook.bas_job,
      auditable: workbook,
      event_type: event_type,
      actor_username: actor_username,
      metadata: {
        bas_tdk_workbook_id: workbook.id,
        status: workbook.status,
        version_number: workbook.version_number,
        source_filename: workbook.source_filename
      }
    )
  rescue ActiveRecord::RecordInvalid
    nil
  end
end
