module Admin
  module Bas
    class ReportsController < Admin::BaseController
      before_action :set_job

      def show
        set_report_context
      end

      def calculate
        snapshot = BasReports::SnapshotBuilder.new(
          bas_job: @job,
          actor_username: current_admin_identifier
        ).create_draft!(notes: params[:notes])

        redirect_to admin_bas_job_report_snapshot_path(@job, snapshot), notice: "Draft BAS report snapshot generated."
      rescue BasReports::SnapshotBuilder::LockedJobError => e
        redirect_to admin_bas_job_report_path(@job), alert: e.message
      end

      private

      def set_job
        @job = BasJob.includes(:bas_client).find(params[:job_id])
      end

      def set_report_context
        @calculation = BasReports::Calculator.new(bas_job: @job).call
        @approval_blockers = BasReports::ApprovalValidator.new(
          bas_job: @job,
          calculation_result: @calculation
        ).call
        @latest_snapshot = @job.report_snapshots.recent.first
        @adjustments = @job.adjustments.recent
        @accepted_matches = @job.matches.accepted.includes(items: :matchable).recent.limit(20)
        @open_queries = @job.queries.open_items.recent
        @audit_events = @job.audit_events.recent.limit(12)
      end
    end
  end
end
