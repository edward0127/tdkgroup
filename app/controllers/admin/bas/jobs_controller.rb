module Admin
  module Bas
    class JobsController < Admin::BaseController
      before_action :set_job, only: [ :show, :edit, :update ]
      before_action :set_clients, only: [ :new, :create, :edit, :update ]

      def index
        @jobs = BasJob.includes(:bas_client).order(period_end: :desc, id: :desc)
      end

      def show
        @documents = @job.documents.with_attached_file.includes(:import_runs, :conversion_runs).ordered
        @documents_by_type = @documents.group_by(&:document_type)
        @import_runs = @job.import_runs.includes(:bas_document).recent.limit(6)
        @bank_transactions = @job.bank_transactions.recent.limit(8)
        @invoices = @job.invoices.recent.limit(8)
        @cash_transactions = @job.cash_transactions.recent.limit(8)
        @payroll_summaries = @job.payroll_summaries.recent.limit(8)
        @proposed_matches_count = @job.matches.proposed.count
        @needs_review_matches_count = @job.matches.needs_review.count
        @accepted_matches_count = @job.matches.accepted.count
        @unmatched_bank_transactions_count = @job.bank_transactions.unmatched.count
        @unmatched_invoices_count = @job.invoices.unmatched.count
        @imported_records_count = @job.bank_transactions.count + @job.invoices.count + @job.cash_transactions.count + @job.payroll_summaries.count
        @latest_report_snapshot = @job.report_snapshots.recent.first
        @approval_blockers_count = BasReports::ApprovalValidator.new(bas_job: @job).call.size
        @ai_config = BasAi::Config.current
        @ai_runs = @job.ai_extraction_runs.recent.limit(5)
        @ai_suggestions_count = @job.ai_suggestions.proposed.count
        @open_queries = @job.queries.open_items.recent
        @audit_events = @job.audit_events.recent.limit(12)
      end

      def new
        @job = BasJob.new(bas_client_id: params[:bas_client_id])
      end

      def create
        @job = BasJob.new(job_params)

        if @job.save
          create_job_audit_event("bas_job_created", changed_fields: [])
          redirect_to admin_bas_job_path(@job), notice: "BAS job created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        previous_status = @job.status
        @job.assign_attributes(job_params)
        changed_fields = @job.changed - %w[internal_notes approved_by locked_by]

        if @job.save
          create_job_audit_event("bas_job_updated", changed_fields: changed_fields)
          if previous_status != @job.status
            create_job_audit_event(
              "bas_job_status_changed",
              previous_status: previous_status,
              status: @job.status
            )
          end
          redirect_to admin_bas_job_path(@job), notice: "BAS job updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def set_job
        @job = BasJob.includes(:bas_client).find(params[:id])
      end

      def set_clients
        @clients = BasClient.ordered
      end

      def job_params
        params.require(:bas_job).permit(
          :bas_client_id,
          :period_start,
          :period_end,
          :quarter_label,
          :status,
          :gst_basis,
          :reporting_method,
          :payroll_applicable,
          :cash_transactions_applicable,
          :internal_notes
        )
      end

      def create_job_audit_event(event_type, metadata)
        BasAuditEvent.create!(
          bas_job: @job,
          auditable: @job,
          event_type: event_type,
          actor_username: current_admin_identifier,
          metadata: metadata.merge(bas_job_id: @job.id, bas_client_id: @job.bas_client_id)
        )
      end
    end
  end
end
