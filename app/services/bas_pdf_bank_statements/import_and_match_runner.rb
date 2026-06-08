module BasPdfBankStatements
  class ImportAndMatchRunner
    Result = Data.define(:conversion_run, :import_run, :imported_count, :proposed_match_count, :open_query_count)

    def initialize(conversion_run:, actor_username:)
      @conversion_run = conversion_run
      @bas_job = conversion_run.bas_job
      @actor_username = actor_username
    end

    def call
      raise ImportRunner::ImportError, "Locked BAS jobs cannot import and match PDF bank statement conversions." if bas_job.locked?

      import_result = ImportRunner.new(
        conversion_run: conversion_run,
        actor_username: actor_username
      ).call

      proposed_match_count = BasMatching::Matcher.new(
        bas_job: bas_job,
        actor_username: actor_username
      ).call

      conversion_run.update!(
        status: "matched",
        matched_at: Time.current,
        matched_by: actor_username
      )
      open_query_count = bas_job.queries.open_items.count
      create_audit_event(import_result.import_run, proposed_match_count, open_query_count)

      Result.new(
        conversion_run: conversion_run,
        import_run: import_result.import_run,
        imported_count: import_result.imported_count,
        proposed_match_count: proposed_match_count,
        open_query_count: open_query_count
      )
    end

    private

    attr_reader :conversion_run, :bas_job, :actor_username

    def create_audit_event(import_run, proposed_match_count, open_query_count)
      BasAuditEvent.create!(
        bas_job: bas_job,
        auditable: conversion_run,
        event_type: "bas_pdf_bank_statement_imported_and_matched",
        actor_username: actor_username,
        metadata: {
          source_bas_document_id: conversion_run.source_bas_document_id,
          bas_document_conversion_run_id: conversion_run.id,
          bas_import_run_id: import_run.id,
          row_count: conversion_run.row_count,
          imported_count: import_run.imported_count,
          error_count: conversion_run.error_count,
          proposed_match_count: proposed_match_count,
          open_query_count: open_query_count,
          status: conversion_run.status,
          detected_bank_name: conversion_run.detected_bank_name
        }.compact
      )
    end
  end
end
