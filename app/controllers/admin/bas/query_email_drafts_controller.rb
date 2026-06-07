module Admin
  module Bas
    class QueryEmailDraftsController < Admin::BaseController
      before_action :set_job

      def show
        @draft = build_draft
        create_draft_audit_event("bas_query_email_draft_generated", @draft.queries)
      end

      def mark_waiting_for_client
        if @job.locked?
          redirect_to admin_bas_job_query_email_draft_path(@job), alert: "Locked BAS jobs cannot change query statuses."
          return
        end

        draft = build_draft
        queries = draft.queries.select { |query| query.status == "open" }
        queries.each do |query|
          query.update!(status: "waiting_for_client", updated_by: current_admin_identifier)
        end

        create_draft_audit_event("bas_queries_marked_waiting_for_client", queries)
        redirect_to admin_bas_job_query_email_draft_path(@job), notice: "#{queries.size} quer#{queries.size == 1 ? 'y' : 'ies'} marked waiting for client."
      end

      private

      def set_job
        @job = BasJob.includes(:bas_client).find(params[:job_id])
      end

      def build_draft
        BasQueries::EmailDraftBuilder.new(bas_job: @job).call
      end

      def create_draft_audit_event(event_type, queries)
        BasAuditEvent.create!(
          bas_job: @job,
          auditable: @job,
          event_type: event_type,
          actor_username: current_admin_identifier,
          metadata: {
            bas_job_id: @job.id,
            bas_client_id: @job.bas_client_id,
            query_count: queries.size,
            query_ids: queries.map(&:id)
          }
        )
      end
    end
  end
end
