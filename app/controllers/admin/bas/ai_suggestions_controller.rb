module Admin
  module Bas
    class AiSuggestionsController < Admin::BaseController
      before_action :set_job
      before_action :set_config
      before_action :set_suggestion, only: [ :show, :accept, :reject, :mark_needs_review ]
      before_action :block_locked_job, only: [ :accept, :reject, :mark_needs_review ]

      def index
        @suggestions = @job.ai_suggestions.includes(:bas_ai_extraction_run).recent
      end

      def show
      end

      def accept
        BasAi::SuggestionApplier.new(
          suggestion: @suggestion,
          actor_username: current_admin_identifier
        ).accept!
        redirect_to admin_bas_job_ai_suggestion_path(@job, @suggestion), notice: "AI suggestion accepted for admin review workflow."
      rescue BasAi::SuggestionApplier::UnsupportedSuggestionError => e
        redirect_to admin_bas_job_ai_suggestion_path(@job, @suggestion), alert: e.message
      end

      def reject
        BasAi::SuggestionApplier.new(
          suggestion: @suggestion,
          actor_username: current_admin_identifier
        ).reject!
        redirect_to admin_bas_job_ai_suggestion_path(@job, @suggestion), notice: "AI suggestion rejected."
      end

      def mark_needs_review
        BasAi::SuggestionApplier.new(
          suggestion: @suggestion,
          actor_username: current_admin_identifier
        ).mark_needs_review!
        redirect_to admin_bas_job_ai_suggestion_path(@job, @suggestion), notice: "AI suggestion marked needs review."
      end

      private

      def set_job
        @job = BasJob.find(params[:job_id])
      end

      def set_config
        @config = BasAi::Config.current
      end

      def set_suggestion
        @suggestion = @job.ai_suggestions.includes(:bas_ai_extraction_run).find(params[:id])
      end

      def block_locked_job
        return unless @job.locked?

        redirect_to admin_bas_job_ai_suggestion_path(@job, @suggestion), alert: "Locked BAS jobs cannot have AI suggestions applied or reviewed."
      end
    end
  end
end
