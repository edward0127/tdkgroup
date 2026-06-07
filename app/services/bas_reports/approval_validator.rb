module BasReports
  class ApprovalValidator
    def initialize(bas_job:, snapshot: nil, require_snapshot: false, calculation_result: nil)
      @bas_job = bas_job
      @snapshot = snapshot
      @require_snapshot = require_snapshot
      @calculation_result = calculation_result
      @blockers = []
    end

    def call
      add_job_blockers
      add_query_blockers
      add_import_error_blockers
      add_match_blockers
      add_record_review_blockers
      add_payroll_blockers
      add_snapshot_blockers
      add_calculation_blockers

      blockers.uniq
    end

    private

    attr_reader :bas_job, :snapshot, :require_snapshot, :calculation_result, :blockers

    def add_job_blockers
      blockers << "GST basis must be set before approval." if bas_job.gst_basis == "unknown"
      blockers << "Reporting method must be set before approval." if bas_job.reporting_method == "unknown"
      blockers << "Cancelled BAS jobs cannot be approved." if bas_job.status == "cancelled"
    end

    def add_query_blockers
      open_count = bas_job.queries.open_items.count
      blockers << "#{open_count} open BAS query item#{'s' unless open_count == 1} must be resolved or dismissed." if open_count.positive?
    end

    def add_import_error_blockers
      bas_job.import_runs.where.not(status: "reverted").find_each do |import_run|
        next if import_run.import_errors.blank?

        blockers << "Import run ##{import_run.id} has row errors that must be resolved or reverted."
      end
    end

    def add_match_blockers
      proposed_count = bas_job.matches.proposed.count
      blockers << "#{proposed_count} proposed match#{'es' unless proposed_count == 1} must be accepted, rejected or marked for review." if proposed_count.positive?

      review_count = bas_job.matches.needs_review.count
      blockers << "#{review_count} match#{'es' unless review_count == 1} marked needs review must be resolved." if review_count.positive?
    end

    def add_record_review_blockers
      unmatched_bank_count = bas_job.bank_transactions.unmatched.count
      blockers << "#{unmatched_bank_count} bank transaction#{'s' unless unmatched_bank_count == 1} remain unmatched." if unmatched_bank_count.positive?

      unmatched_invoice_count = bas_job.invoices.unmatched.count
      blockers << "#{unmatched_invoice_count} invoice#{'s' unless unmatched_invoice_count == 1} remain unmatched." if unmatched_invoice_count.positive?

      invoice_direction_count = active_invoices.where(direction: "unknown").count
      blockers << "#{invoice_direction_count} invoice#{'s' unless invoice_direction_count == 1} have unknown direction." if invoice_direction_count.positive?

      cash_direction_count = active_cash_transactions.where(direction: "unknown").count
      blockers << "#{cash_direction_count} cash transaction#{'s' unless cash_direction_count == 1} have unknown direction." if cash_direction_count.positive?

      invoice_review_count = active_invoices.where("status = ? OR gst_code IN (?)", "needs_review", %w[unknown needs_review]).count
      blockers << "#{invoice_review_count} invoice#{'s' unless invoice_review_count == 1} need GST or status review." if invoice_review_count.positive?

      cash_review_count = active_cash_transactions.where("status = ? OR gst_code IN (?)", "needs_review", %w[unknown needs_review]).count
      blockers << "#{cash_review_count} cash transaction#{'s' unless cash_review_count == 1} need GST or status review." if cash_review_count.positive?
    end

    def active_invoices
      bas_job.invoices.where.not(status: "ignored").where.not(gst_code: "bas_excluded")
    end

    def active_cash_transactions
      bas_job.cash_transactions.where.not(status: "ignored").where.not(gst_code: "bas_excluded")
    end

    def add_payroll_blockers
      return unless bas_job.payroll_applicable?
      return if bas_job.payroll_summaries.exists?
      return if bas_job.adjustments.where(adjustment_type: %w[payroll_gross_wages payg_withheld]).exists?

      blockers << "Payroll is marked applicable but no payroll summary or manual payroll adjustment exists."
    end

    def add_snapshot_blockers
      return unless require_snapshot

      if snapshot.blank?
        blockers << "A draft report snapshot must exist before approval."
      elsif snapshot.validation_errors.present?
        blockers << "The selected report snapshot contains validation blockers."
      end
    end

    def add_calculation_blockers
      result = calculation_result || BasReports::Calculator.new(bas_job: bas_job).call
      blockers.concat(result.validation_errors)
    end
  end
end
