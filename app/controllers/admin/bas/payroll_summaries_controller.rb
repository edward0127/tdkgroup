module Admin
  module Bas
    class PayrollSummariesController < Admin::BaseController
      def index
        @job = BasJob.find(params[:job_id])
        @import_runs = @job.import_runs.recent
        @payroll_summaries = filtered_scope.limit(250)
      end

      private

      def filtered_scope
        scope = @job.payroll_summaries.includes(:bas_import_run).recent
        scope = scope.where(bas_import_run_id: params[:import_run_id]) if params[:import_run_id].present?
        scope
      end
    end
  end
end
