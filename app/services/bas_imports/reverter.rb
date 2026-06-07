module BasImports
  class Reverter
    class LockedJobError < StandardError; end

    def initialize(import_run:, actor_username:)
      @import_run = import_run
      @bas_job = import_run.bas_job
      @actor_username = actor_username
    end

    def call
      raise LockedJobError, "locked BAS jobs cannot have imports reverted" if bas_job.locked?

      deleted_counts = {}

      BasImportRun.transaction do
        deleted_counts[:bank_transactions] = BasBankTransaction.where(bas_import_run: import_run).delete_all
        deleted_counts[:invoices] = BasInvoice.where(bas_import_run: import_run).delete_all
        deleted_counts[:cash_transactions] = BasCashTransaction.where(bas_import_run: import_run).delete_all
        deleted_counts[:payroll_summaries] = BasPayrollSummary.where(bas_import_run: import_run).delete_all

        import_run.update!(status: "reverted")
        create_audit_event(deleted_counts)
      end

      import_run
    end

    private

    attr_reader :import_run, :bas_job, :actor_username

    def create_audit_event(deleted_counts)
      BasAuditEvent.create!(
        bas_job: bas_job,
        auditable: import_run,
        event_type: "bas_import_reverted",
        actor_username: actor_username,
        metadata: {
          bas_import_run_id: import_run.id,
          bas_document_id: import_run.bas_document_id,
          import_type: import_run.import_type,
          status: import_run.status,
          imported_count: import_run.imported_count,
          deleted_counts: deleted_counts,
          filename: import_run.bas_document.safe_filename
        }
      )
    end
  end
end
