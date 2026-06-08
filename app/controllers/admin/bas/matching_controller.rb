module Admin
  module Bas
    class MatchingController < Admin::BaseController
      before_action :set_job
      before_action :block_locked_job, only: [ :run, :generate_queries ]

      def show
        set_summary
      end

      def run
        created_count = BasMatching::Matcher.new(
          bas_job: @job,
          actor_username: current_admin_identifier
        ).call

        redirect_to admin_bas_job_matching_path(@job), notice: "Matching suggestions created. #{created_count} proposed matches created."
      end

      def generate_queries
        if matching_review_open?
          redirect_to admin_bas_job_matching_path(@job), alert: "Review proposed and needs-review matches before generating client queries."
          return
        end

        created_count = BasMatching::QueryGenerator.new(
          bas_job: @job,
          actor_username: current_admin_identifier
        ).call

        redirect_to admin_bas_job_matching_path(@job), notice: "Client query generation completed. #{created_count} queries created."
      end

      private

      def set_job
        @job = BasJob.find(params[:job_id])
      end

      def set_summary
        @summary = {
          proposed_matches: @job.matches.proposed.count,
          needs_review_matches: @job.matches.needs_review.count,
          accepted_matches: @job.matches.accepted.count,
          rejected_matches: @job.matches.rejected.count,
          unmatched_bank_transactions: @job.bank_transactions.unmatched.count,
          unmatched_invoices: @job.invoices.unmatched.count,
          open_queries: @job.queries.open_items.count
        }
        @proposed_matches = @job.matches.includes(items: :matchable).proposed.recent.limit(20)
      end

      def matching_review_open?
        @job.matches.proposed.exists? || @job.matches.needs_review.exists?
      end

      def block_locked_job
        return unless @job.locked?

        redirect_to admin_bas_job_matching_path(@job), alert: "Locked BAS jobs cannot run matching or generate queries."
      end
    end
  end
end
