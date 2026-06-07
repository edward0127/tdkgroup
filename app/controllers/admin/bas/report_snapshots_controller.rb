module Admin
  module Bas
    class ReportSnapshotsController < Admin::BaseController
      before_action :set_job
      before_action :set_snapshot, only: [
        :show,
        :approve,
        :lock,
        :download_summary_csv,
        :download_gst_detail_csv,
        :download_matches_csv,
        :download_queries_csv,
        :download_adjustments_csv,
        :print
      ]

      def index
        @snapshots = @job.report_snapshots.recent
      end

      def show
      end

      def create
        snapshot = BasReports::SnapshotBuilder.new(
          bas_job: @job,
          actor_username: current_admin_identifier
        ).create_draft!(notes: params[:notes])

        redirect_to admin_bas_job_report_snapshot_path(@job, snapshot), notice: "Draft BAS report snapshot generated."
      rescue BasReports::SnapshotBuilder::LockedJobError => e
        redirect_to admin_bas_job_report_path(@job), alert: e.message
      end

      def approve
        BasReports::SnapshotBuilder.new(
          bas_job: @job,
          actor_username: current_admin_identifier
        ).approve!(snapshot: @snapshot)

        redirect_to admin_bas_job_report_snapshot_path(@job, @snapshot), notice: "BAS report snapshot approved."
      rescue BasReports::SnapshotBuilder::ApprovalBlockedError => e
        redirect_to admin_bas_job_report_snapshot_path(@job, @snapshot), alert: "Approval blocked: #{e.blockers.to_sentence}"
      rescue BasReports::SnapshotBuilder::LockedJobError => e
        redirect_to admin_bas_job_report_snapshot_path(@job, @snapshot), alert: e.message
      end

      def lock
        BasReports::SnapshotBuilder.new(
          bas_job: @job,
          actor_username: current_admin_identifier
        ).lock!(snapshot: @snapshot)

        redirect_to admin_bas_job_report_snapshot_path(@job, @snapshot), notice: "BAS job locked."
      rescue BasReports::SnapshotBuilder::LockedJobError => e
        redirect_to admin_bas_job_report_snapshot_path(@job, @snapshot), alert: e.message
      end

      def download_summary_csv
        send_csv(:summary_csv, "bas-summary")
      end

      def download_gst_detail_csv
        send_csv(:gst_detail_csv, "bas-gst-detail")
      end

      def download_matches_csv
        send_csv(:matches_csv, "bas-accepted-matches")
      end

      def download_queries_csv
        send_csv(:queries_csv, "bas-queries")
      end

      def download_adjustments_csv
        send_csv(:adjustments_csv, "bas-adjustments")
      end

      def print
        render :print
      end

      private

      def set_job
        @job = BasJob.includes(:bas_client).find(params[:job_id])
      end

      def set_snapshot
        @snapshot = @job.report_snapshots.find(params[:id])
      end

      def send_csv(method_name, filename_prefix)
        csv = BasReports::CsvExporter.new(snapshot: @snapshot).public_send(method_name)
        send_data(
          csv,
          filename: "#{filename_prefix}-job-#{@job.id}-snapshot-#{@snapshot.id}.csv",
          type: "text/csv; charset=utf-8",
          disposition: "attachment"
        )
      end
    end
  end
end
