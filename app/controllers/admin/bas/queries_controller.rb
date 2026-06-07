module Admin
  module Bas
    class QueriesController < Admin::BaseController
      before_action :set_job
      before_action :set_query, only: [ :show, :edit, :update ]
      before_action :block_locked_job, only: [ :new, :create, :edit, :update ]

      def index
        @queries = @job.queries.recent
      end

      def show
      end

      def new
        @query = @job.queries.build
      end

      def create
        @query = @job.queries.build(query_params)
        @query.created_by = current_admin_identifier
        @query.updated_by = current_admin_identifier

        if @query.save
          create_query_audit_event("bas_query_created")
          redirect_to admin_bas_job_path(@job), notice: "BAS query created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        previous_status = @query.status
        @query.assign_attributes(query_params)
        @query.updated_by = current_admin_identifier

        if @query.save
          create_query_audit_event("bas_query_updated", previous_status: previous_status, status: @query.status)
          if previous_status != @query.status && @query.status == "resolved"
            create_query_audit_event("bas_query_resolved")
          elsif previous_status != @query.status && @query.status == "dismissed"
            create_query_audit_event("bas_query_dismissed")
          end
          redirect_to admin_bas_job_path(@job), notice: "BAS query updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def set_job
        @job = BasJob.find(params[:job_id])
      end

      def set_query
        @query = @job.queries.find(params[:id])
      end

      def block_locked_job
        return unless @job.locked?

        redirect_to admin_bas_job_path(@job), alert: "Locked BAS jobs cannot have queries changed."
      end

      def query_params
        params.require(:bas_query).permit(
          :query_type,
          :status,
          :title,
          :details,
          :resolution_notes
        )
      end

      def create_query_audit_event(event_type, metadata = {})
        BasAuditEvent.create!(
          bas_job: @job,
          auditable: @query,
          event_type: event_type,
          actor_username: current_admin_identifier,
          metadata: metadata.merge(bas_query_id: @query.id, query_type: @query.query_type)
        )
      end
    end
  end
end
