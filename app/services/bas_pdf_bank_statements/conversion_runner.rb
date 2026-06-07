module BasPdfBankStatements
  class ConversionRunner
    class LockedJobError < StandardError; end

    def initialize(bas_job:, source_bas_document:, actor_username:)
      @bas_job = bas_job
      @source_bas_document = source_bas_document
      @actor_username = actor_username
    end

    def call
      raise LockedJobError, "locked BAS jobs cannot create document conversions" if bas_job.locked?

      run = create_run!
      create_audit_event(run, "bas_pdf_bank_statement_conversion_started")

      extracted = TextExtractor.new(bas_document: source_bas_document).call
      parsed = TransactionParser.new(text: extracted.text).call
      scored = ConfidenceScorer.new(rows: parsed.rows).call

      if scored.rows.blank?
        fail_run!(run, "No bank transaction rows could be detected in this PDF.")
      else
        preview_run!(run, extracted: extracted, parsed: parsed, scored: scored)
      end

      run
    rescue TextExtractor::ExtractionError => e
      run ||= create_run!
      fail_run!(run, e.message)
      run
    end

    private

    attr_reader :bas_job, :source_bas_document, :actor_username

    def create_run!
      BasDocumentConversionRun.create!(
        bas_job: bas_job,
        source_bas_document: source_bas_document,
        conversion_type: "bank_statement_pdf",
        status: "running",
        converted_by: actor_username,
        metadata: {
          source_bas_document_id: source_bas_document.id
        }
      )
    end

    def preview_run!(run, extracted:, parsed:, scored:)
      run.update!(
        status: "previewed",
        detected_bank_name: parsed.detected_bank_name,
        page_count: extracted.page_count,
        row_count: scored.rows.size,
        converted_count: scored.rows.count { |row| Array(row["warnings"]).blank? },
        error_count: scored.row_errors.size,
        preview_rows: scored.rows,
        row_errors: scored.row_errors,
        converted_at: Time.current,
        metadata: run.metadata.merge(
          csv_headers: CsvBuilder::HEADERS,
          parser: "standard_text_bank_statement"
        )
      )
      create_audit_event(run, "bas_pdf_bank_statement_conversion_previewed")
    end

    def fail_run!(run, message)
      run.update!(
        status: "failed",
        error_count: 1,
        row_errors: [ { "row_number" => nil, "message" => message } ],
        converted_at: Time.current
      )
      create_audit_event(run, "bas_pdf_bank_statement_conversion_failed")
    end

    def create_audit_event(run, event_type)
      BasAuditEvent.create!(
        bas_job: bas_job,
        auditable: run,
        event_type: event_type,
        actor_username: actor_username,
        metadata: safe_metadata(run)
      )
    end

    def safe_metadata(run)
      {
        source_bas_document_id: source_bas_document.id,
        bas_document_conversion_run_id: run.id,
        row_count: run.row_count,
        error_count: run.error_count,
        status: run.status,
        detected_bank_name: run.detected_bank_name
      }.compact
    end
  end
end
