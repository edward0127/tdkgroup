module Admin
  module Bas
    class JobNextStepPresenter
      include Rails.application.routes.url_helpers

      attr_reader :job

      def initialize(job:)
        @job = job
      end

      def title
        step.fetch(:title)
      end

      def reason
        step.fetch(:reason)
      end

      def action_label
        step[:action_label]
      end

      def action_path
        step[:action_path]
      end

      def action?
        action_label.present? && action_path.present?
      end

      def status
        step.fetch(:status)
      end

      private

      def step
        @step ||= build_step
      end

      def build_step
        return locked_step if job.locked?
        return upload_files_step if imported_records_count.zero? && (documents_count.zero? || importable_documents_count.zero?)
        return fix_import_errors_step if import_errors?
        return import_files_step if importable_documents_count.positive? && imported_records_count.zero?
        return create_match_suggestions_step if imported_records_count.positive? && matches_count.zero?
        return review_matches_step if matching_review_count.positive?
        return resolve_queries_step if open_queries_count.positive?
        return generate_queries_step if unresolved_items_count.positive? && !queries_generated?
        return calculate_draft_step if latest_snapshot.blank?
        return lock_job_step if latest_snapshot.final?

        review_draft_step
      end

      def locked_step
        {
          title: "BAS job locked",
          reason: "This BAS job is locked and workflow actions are read-only.",
          status: "Locked"
        }
      end

      def upload_files_step
        {
          title: "Next step: Upload source files",
          reason: upload_files_reason,
          action_label: "Upload source file",
          action_path: new_admin_bas_job_document_path(job),
          status: "Action required"
        }
      end

      def import_files_step
        {
          title: "Next step: Import uploaded files",
          reason: "Source files are uploaded, but no structured BAS records have been imported yet.",
          action_label: "Import uploaded files",
          action_path: admin_bas_job_import_runs_path(job),
          status: "Action required"
        }
      end

      def fix_import_errors_step
        {
          title: "Next step: Fix import errors",
          reason: "One or more import runs has row errors that need review before the workflow continues.",
          action_label: "Review imports",
          action_path: admin_bas_job_import_runs_path(job),
          status: "Action required"
        }
      end

      def create_match_suggestions_step
        {
          title: "Next step: Create match suggestions",
          reason: "Structured records have been imported. Create matching suggestions before generating client queries.",
          action_label: "Go to matching",
          action_path: admin_bas_job_matching_path(job),
          status: "Action required"
        }
      end

      def review_matches_step
        {
          title: "Next step: Review match suggestions",
          reason: "#{matching_review_count} proposed or needs-review #{'match'.pluralize(matching_review_count)} must be accepted, rejected, or marked for follow-up before client queries are generated.",
          action_label: "Review matches",
          action_path: admin_bas_job_matching_path(job),
          status: "Action required"
        }
      end

      def generate_queries_step
        {
          title: "Next step: Generate client queries",
          reason: "Matching review is clear, but unmatched or unresolved items still need client/internal queries.",
          action_label: "Generate client queries",
          action_path: admin_bas_job_matching_path(job),
          status: "Action required"
        }
      end

      def resolve_queries_step
        {
          title: "Next step: Resolve open queries",
          reason: "#{open_queries_count} open #{'query'.pluralize(open_queries_count)} should be resolved or dismissed before final approval.",
          action_label: "Review queries",
          action_path: admin_bas_job_path(job, tab: "matching", anchor: "open-queries"),
          status: "Action required"
        }
      end

      def calculate_draft_step
        {
          title: "Next step: Calculate BAS draft",
          reason: "The job is ready for a draft BAS calculation and review snapshot.",
          action_label: "Calculate BAS report",
          action_path: admin_bas_job_report_path(job),
          status: "Ready"
        }
      end

      def review_draft_step
        {
          title: "Next step: Review draft snapshot",
          reason: "A draft snapshot exists. Review blockers and figures before final approval.",
          action_label: "Review report",
          action_path: admin_bas_job_report_snapshot_path(job, latest_snapshot),
          status: "Review"
        }
      end

      def lock_job_step
        {
          title: "Next step: Lock BAS job",
          reason: "The latest snapshot is final. Lock the BAS job when staff review is complete.",
          action_label: "Lock job",
          action_path: admin_bas_job_report_snapshot_path(job, latest_snapshot),
          status: "Ready to lock"
        }
      end

      def documents_count
        @documents_count ||= job.documents.count
      end

      def upload_files_reason
        return "No source files have been uploaded for this BAS period yet." if documents_count.zero?

        "Only supporting files have been uploaded. Upload bank, invoice, cash transaction, or payroll source files before importing BAS records."
      end

      def importable_documents_count
        @importable_documents_count ||= job.documents.where(document_type: %w[
          bank_statement
          invoice_summary
          cash_transaction_list
          payroll_summary
        ]).count
      end

      def imported_records_count
        @imported_records_count ||= job.bank_transactions.count +
          job.invoices.count +
          job.cash_transactions.count +
          job.payroll_summaries.count
      end

      def import_errors?
        @import_errors ||= job.import_runs.any? do |import_run|
          import_run.status == "failed" ||
            import_run.error_count.to_i.positive? ||
            import_run.import_errors.any?
        end
      end

      def matches_count
        @matches_count ||= job.matches.count
      end

      def proposed_matches_count
        @proposed_matches_count ||= job.matches.proposed.count
      end

      def needs_review_matches_count
        @needs_review_matches_count ||= job.matches.needs_review.count
      end

      def matching_review_count
        proposed_matches_count + needs_review_matches_count
      end

      def open_queries_count
        @open_queries_count ||= job.queries.open_items.count
      end

      def queries_generated?
        @queries_generated ||= job.queries.exists?
      end

      def unresolved_items_count
        @unresolved_items_count ||= job.bank_transactions.unmatched.count +
          job.invoices.unmatched.count +
          job.cash_transactions.unmatched.count
      end

      def latest_snapshot
        @latest_snapshot ||= job.report_snapshots.recent.first
      end
    end
  end
end
