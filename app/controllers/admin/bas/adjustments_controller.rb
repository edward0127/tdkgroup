module Admin
  module Bas
    class AdjustmentsController < Admin::BaseController
      before_action :set_job
      before_action :set_adjustment, only: [ :edit, :update, :destroy ]
      before_action :block_locked_job, only: [ :new, :create, :edit, :update, :destroy ]

      def index
        @adjustments = @job.adjustments.recent
      end

      def new
        @adjustment = @job.adjustments.build
      end

      def create
        @adjustment = @job.adjustments.build(adjustment_params)
        @adjustment.created_by = current_admin_identifier

        if @adjustment.save
          create_adjustment_audit_event("bas_adjustment_created")
          redirect_to admin_bas_job_report_path(@job), notice: "BAS adjustment added."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @adjustment.update(adjustment_params)
          create_adjustment_audit_event("bas_adjustment_updated")
          redirect_to admin_bas_job_report_path(@job), notice: "BAS adjustment updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        metadata = adjustment_metadata

        if @adjustment.destroy
          BasAuditEvent.create!(
            bas_job: @job,
            event_type: "bas_adjustment_deleted",
            actor_username: current_admin_identifier,
            metadata: metadata
          )
          redirect_to admin_bas_job_report_path(@job), notice: "BAS adjustment deleted."
        else
          redirect_to admin_bas_job_report_path(@job), alert: @adjustment.errors.full_messages.to_sentence
        end
      end

      private

      def set_job
        @job = BasJob.find(params[:job_id])
      end

      def set_adjustment
        @adjustment = @job.adjustments.find(params[:id])
      end

      def adjustment_params
        params.require(:bas_adjustment).permit(:adjustment_type, :label, :amount, :reason)
      end

      def create_adjustment_audit_event(event_type)
        BasAuditEvent.create!(
          bas_job: @job,
          auditable: @adjustment,
          event_type: event_type,
          actor_username: current_admin_identifier,
          metadata: adjustment_metadata
        )
      end

      def adjustment_metadata
        {
          bas_adjustment_id: @adjustment.id,
          adjustment_type: @adjustment.adjustment_type,
          label: @adjustment.label
        }
      end

      def block_locked_job
        return unless @job.locked?

        redirect_to admin_bas_job_report_path(@job), alert: "Locked BAS jobs cannot have adjustments changed."
      end
    end
  end
end
