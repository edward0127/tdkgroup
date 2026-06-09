module Admin
  module Bas
    class AiRunsController < Admin::BaseController
      before_action :set_job
      before_action :set_config
      before_action :set_run, only: [ :show ]
      before_action :block_locked_job, only: [ :create ]

      def index
        @runs = @job.ai_extraction_runs.includes(:bas_document).recent
        @ai_readiness = readiness_checker
      end

      def show
        @suggestions = @run.ai_suggestions.recent
      end

      def create
        input_kind = requested_input_kind

        if @config.openai_provider? && document_input_kind?(input_kind)
          redirect_to admin_bas_job_ai_runs_path(@job), alert: BasAi::OpenaiProvider::DOCUMENT_TEXT_DISABLED_MESSAGE
          return
        end

        unless @config.ui_enabled?
          redirect_to admin_bas_job_path(@job), alert: "AI review is currently disabled."
          return
        end

        if input_kind == "job_review" && !readiness_checker.ready?
          redirect_to admin_bas_job_ai_runs_path(@job),
            alert: "AI Job review is available after the main BAS workflow has enough structured data."
          return
        end

        if (active_run = active_ai_run(input_kind))
          redirect_to admin_bas_job_ai_run_path(@job, active_run),
            alert: "An AI review is already running for this job. Please wait for it to finish."
          return
        end

        run = BasAiExtractionJob.perform_now(
          bas_job_id: @job.id,
          bas_document_id: document_input_kind?(input_kind) ? ai_run_params[:bas_document_id].presence : nil,
          input_kind: input_kind,
          actor_username: current_admin_identifier
        )

        if run
          flash_type, message = ai_run_flash(run)
          flash.delete(:notice) if flash_type == :alert
          redirect_to admin_bas_job_ai_run_path(@job, run), flash_type => message
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

      def requested_input_kind
        input_kind = ai_run_params[:input_kind].presence || "job_review"
        return input_kind if BasAiExtractionRun::INPUT_KIND_VALUES.include?(input_kind)

        "job_review"
      end

      def document_input_kind?(input_kind)
        input_kind.in?(BasAiExtractionRun::DOCUMENT_INPUT_KIND_VALUES)
      end

      def active_ai_run(input_kind)
        @job.ai_extraction_runs.where(input_kind: input_kind, status: %w[pending running]).recent.first
      end

      def readiness_checker
        @readiness_checker ||= BasAi::ReadinessChecker.new(bas_job: @job)
      end

      def ai_run_flash(run)
        case run.status
        when "completed"
          [ :notice, completed_ai_run_message(run) ]
        when "failed"
          [ :alert, "AI review failed. No AI suggestions were created." ]
        else
          [ :notice, "AI review #{run.status.humanize.downcase}." ]
        end
      end

      def completed_ai_run_message(run)
        count = run.ai_suggestions.count
        return "AI review completed. No AI suggestions were created." if count.zero?

        "AI review completed. #{count} #{'suggestion'.pluralize(count)} created for accountant review."
      end

      def block_locked_job
        return unless @job.locked?

        redirect_to admin_bas_job_ai_runs_path(@job), alert: "Locked BAS jobs cannot start AI runs."
      end
    end
  end
end
