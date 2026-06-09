module BasAi
  class ReadinessChecker
    attr_reader :bas_job

    def initialize(bas_job:)
      @bas_job = bas_job
    end

    def ready?
      blockers.empty?
    end

    def blockers
      @blockers ||= build_blockers
    end

    def warnings
      @warnings ||= build_warnings
    end

    private

    def build_blockers
      [].tap do |items|
        items << "BAS job is locked." if bas_job.locked?
        items << "GST basis is unknown." if bas_job.gst_basis == "unknown"
        items << "Reporting method is unknown." if bas_job.reporting_method == "unknown"
        items << "Import structured BAS records before running AI review." if imported_records_count.zero?
        items << "Resolve import row errors before running AI review." if import_errors?
        items << "Review proposed match suggestions before running AI review." if bas_job.matches.proposed.exists?
        items << "Resolve needs-review matches before running AI review." if bas_job.matches.needs_review.exists?
      end
    end

    def build_warnings
      [].tap do |items|
        items << "No client/internal queries have been generated yet." unless bas_job.queries.exists?
        items << "No report snapshot exists yet." unless bas_job.report_snapshots.exists?
        items << "Payroll is marked applicable, but no payroll summary exists." if bas_job.payroll_applicable? && !bas_job.payroll_summaries.exists?
        items << "Cash transactions are marked applicable, but no cash transactions exist." if bas_job.cash_transactions_applicable? && !bas_job.cash_transactions.exists?
      end
    end

    def imported_records_count
      @imported_records_count ||= bas_job.bank_transactions.count +
        bas_job.invoices.count +
        bas_job.cash_transactions.count +
        bas_job.payroll_summaries.count
    end

    def import_errors?
      @import_errors ||= bas_job.import_runs.any? do |import_run|
        import_run.status == "failed" ||
          import_run.error_count.to_i.positive? ||
          import_run.import_errors.any?
      end
    end
  end
end
