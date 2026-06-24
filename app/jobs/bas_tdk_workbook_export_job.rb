require "stringio"

class BasTdkWorkbookExportJob < ApplicationJob
  queue_as :default

  def perform(workbook_id:, actor_username: "admin")
    workbook = BasTdkWorkbook.find_by(id: workbook_id)
    return if workbook.blank? || !workbook.processed? || !workbook.active_processed?
    return unless claim_export(workbook, actor_username)

    create_audit_event(workbook, "bas_tdk_workbook_export_started", actor_username)
    source_updated_at = workbook.updated_at

    data = BasTdk::WorkbookExporter.new(workbook: workbook).call
    workbook.with_lock do
      workbook.reload
      return if workbook.export_status == "stale" && workbook.updated_at > source_updated_at

      workbook.export_file.attach(
        io: StringIO.new(data),
        filename: workbook.download_filename,
        content_type: BasTdk::WorkbookExporter::XLSX_CONTENT_TYPE
      )
      workbook.update!(
        export_status: "processed",
        export_finished_at: Time.current,
        export_generated_at: Time.current,
        export_error: nil
      )
    end

    create_audit_event(workbook, "bas_tdk_workbook_export_completed", actor_username)
  rescue StandardError => e
    mark_failed_safely(workbook_id, actor_username, e)
  end

  private

  def claim_export(workbook, actor_username)
    workbook.with_lock do
      workbook.reload
      return false unless workbook.processed? && workbook.active_processed? && workbook.export_status == "queued"

      workbook.update!(
        export_status: "processing",
        export_started_at: Time.current,
        export_finished_at: nil,
        export_error: nil,
        export_requested_by: actor_username
      )
      true
    end
  end

  def mark_failed_safely(workbook_id, actor_username, exception)
    workbook = BasTdkWorkbook.find_by(id: workbook_id)
    return if workbook.blank?

    workbook.update!(
      export_status: "failed",
      export_finished_at: Time.current,
      export_error: "Excel export could not be prepared. Please try again."
    )
    workbook.metadata = workbook.metadata.merge(
      "export_exception_class" => exception.class.name,
      "export_exception_message" => exception.message.to_s
    )
    workbook.save!
    create_audit_event(workbook, "bas_tdk_workbook_export_failed", actor_username)
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
        export_status: workbook.export_status,
        version_number: workbook.version_number,
        source_filename: workbook.source_filename
      }
    )
  rescue ActiveRecord::RecordInvalid
    nil
  end
end
