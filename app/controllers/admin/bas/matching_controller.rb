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
          redirect_to admin_bas_job_matching_path(@job), alert: "Review #{matching_review_open_count} proposed/needs-review matches before generating client queries."
          return
        end

        generator = BasMatching::QueryGenerator.new(
          bas_job: @job,
          actor_username: current_admin_identifier
        )
        created_count = generator.call

        redirect_to admin_bas_job_matching_path(@job, anchor: "open-client-queries"), notice: query_generation_notice(created_count, generator.existing_count)
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
        matching_review_open_count.positive?
      end

      def matching_review_open_count
        @job.matches.proposed.count + @job.matches.needs_review.count
      end

      def query_generation_notice(created_count, existing_count)
        messages = []
        if created_count.positive?
          messages << "#{created_count} client #{'query'.pluralize(created_count)} generated."
        else
          messages << "No new client queries needed."
        end
        if existing_count.positive?
          messages << "#{existing_count} existing #{'query'.pluralize(existing_count)} already covered these unresolved items."
        end

        messages.join(" ")
      end

      def block_locked_job
        return unless @job.locked?

        redirect_to admin_bas_job_matching_path(@job), alert: "Locked BAS jobs cannot run matching or generate queries."
      end
    end
  end
end
