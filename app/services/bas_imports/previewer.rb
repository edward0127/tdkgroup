module BasImports
  class Previewer
    class LockedJobError < StandardError; end

    PREVIEW_LIMIT = 5

    def initialize(bas_job:, bas_document:, import_type:, actor_username:)
      @bas_job = bas_job
      @bas_document = bas_document
      @import_type = import_type
      @actor_username = actor_username
    end

    def call
      raise LockedJobError, "locked BAS jobs cannot create import runs" if bas_job.locked?

      result = FileReader.read(bas_document)
      import_run = BasImportRun.new(
        bas_job: bas_job,
        bas_document: bas_document,
        import_type: import_type,
        status: "previewed",
        column_mapping: ColumnNormalizer.suggest_mapping(result.headers, import_type),
        preview_rows: result.rows.first(PREVIEW_LIMIT),
        row_count: result.rows.size
      )
      import_run.import_errors = []
      import_run.save!

      create_audit_event(import_run, "bas_import_previewed")
      import_run
    rescue FileReader::ReadError, FileReader::UnsupportedFileError => e
      import_run = BasImportRun.new(
        bas_job: bas_job,
        bas_document: bas_document,
        import_type: import_type,
        status: "failed"
      )
      import_run.import_errors = [ { "row_number" => nil, "message" => e.message } ]
      import_run.error_count = 1
      import_run.save!
      create_audit_event(import_run, "bas_import_failed")
      import_run
    end

    private

    attr_reader :bas_job, :bas_document, :import_type, :actor_username

    def create_audit_event(import_run, event_type)
      BasAuditEvent.create!(
        bas_job: bas_job,
        auditable: import_run,
        event_type: event_type,
        actor_username: actor_username,
        metadata: safe_metadata(import_run)
      )
    end

    def safe_metadata(import_run)
      {
        bas_import_run_id: import_run.id,
        bas_document_id: bas_document.id,
        import_type: import_run.import_type,
        status: import_run.status,
        row_count: import_run.row_count,
        imported_count: import_run.imported_count,
        error_count: import_run.error_count,
        filename: bas_document.safe_filename
      }
    end
  end
end
