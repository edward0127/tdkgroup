module Admin
  module Bas
    class DocumentsController < Admin::BaseController
      before_action :set_job
      before_action :set_document, only: [ :show, :download, :destroy ]

      def index
        @documents = @job.documents.with_attached_file.includes(:import_runs, :conversion_runs).ordered
      end

      def show
      end

      def new
        @document = @job.documents.build
      end

      def create
        @document = @job.documents.build(document_params)
        @document.uploaded_by = current_admin_identifier

        if @document.save
          BasAuditEvent.create!(
            bas_job: @job,
            auditable: @document,
            event_type: "bas_document_uploaded",
            actor_username: current_admin_identifier,
            metadata: {
              bas_document_id: @document.id,
              document_type: @document.document_type,
              filename: @document.safe_filename
            }
          )
          redirect_to admin_bas_job_path(@job), notice: "BAS document uploaded."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def download
        send_data(
          @document.file.download,
          filename: @document.safe_filename,
          type: @document.file.blob.content_type,
          disposition: "attachment"
        )
      end

      def destroy
        if @job.locked?
          redirect_to admin_bas_job_path(@job), alert: "Locked BAS jobs cannot have documents deleted."
          return
        end

        document_id = @document.id
        document_type = @document.document_type
        filename = @document.safe_filename
        @document.destroy

        BasAuditEvent.create!(
          bas_job: @job,
          event_type: "bas_document_deleted",
          actor_username: current_admin_identifier,
          metadata: {
            bas_document_id: document_id,
            document_type: document_type,
            filename: filename
          }
        )

        redirect_to admin_bas_job_path(@job), notice: "BAS document deleted."
      end

      private

      def set_job
        @job = BasJob.find(params[:job_id])
      end

      def set_document
        @document = @job.documents.with_attached_file.find(params[:id])
      end

      def document_params
        params.require(:bas_document).permit(:document_type, :title, :file, :notes)
      end
    end
  end
end
