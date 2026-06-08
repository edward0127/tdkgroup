module Admin
  module Bas
    class DashboardController < Admin::BaseController
      def show
        @active_client_count = BasClient.active.count
        @open_job_count = BasJob.open.count
        @jobs_with_open_queries_count = BasJob.joins(:queries).merge(BasQuery.open_items).distinct.count
        @recent_jobs = BasJob.includes(:bas_client, :report_snapshots).recently_updated.limit(8)
      end
    end
  end
end
