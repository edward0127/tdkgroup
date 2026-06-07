module Admin
  module Bas
    class AiRunsController < Admin::BaseController
      before_action :set_job
      before_action :set_config
      before_action :set_run, only: [ :show ]
      before_action :block_locked_job, only: [ :create ]

      def index
        @runs = @job.ai_extraction_runs.includes(:bas_document).recent
        @documents = @job.documents.with_attached_file.ordered
      end

      def show
        @suggestions = @run.ai_suggestions.recent
      end

      def create
        run = BasAiExtractionJob.perform_now(
          bas_job_id: @job.id,
          bas_document_id: ai_run_params[:bas_document_id].presence,
          input_kind: ai_run_params[:input_kind].presence || "job_review",
          actor_username: current_admin_identifier
        )

        if run
          redirect_to admin_bas_job_ai_run_path(@job, run), notice: ai_run_notice(run)
        else
          redirect_to admin_bas_job_ai_runs_path(@job), alert: "AI run could not be created."
        end
      end

      private

      def set_job
        @job = BasJob.find(params[:job_id])
      end

      def set_config
        @config = BasAi::Config.current
      end

      def set_run
        @run = @job.ai_extraction_runs.includes(:bas_document).find(params[:id])
      end

      def ai_run_params
        params.fetch(:bas_ai_extraction_run, {}).permit(:input_kind, :bas_document_id)
      end

      def ai_run_notice(run)
        run.status == "completed" ? "AI run completed." : "AI run finished with #{run.status.humanize.downcase} status."
      end

      def block_locked_job
        return unless @job.locked?

        redirect_to admin_bas_job_ai_runs_path(@job), alert: "Locked BAS jobs cannot start AI runs."
      end
    end
  end
end
