module Admin
  module Bas
    class ImportRunsController < Admin::BaseController
      include Admin::Bas::WorkflowHelper

      before_action :set_job
      before_action :set_import_run, only: [ :show, :confirm, :revert ]
      before_action :block_locked_job, only: [ :new, :create, :confirm, :revert ]

      def index
        @import_runs = @job.import_runs.includes(:bas_document).recent
      end

      def new
        @documents = importable_documents
        @non_importable_documents = non_importable_documents
        @import_run = @job.import_runs.build
        preselect_document
      end

      def create
        document = @job.documents.find(import_run_params[:bas_document_id])
        unless bas_spreadsheet_importable_document?(document)
          @documents = importable_documents
          @non_importable_documents = non_importable_documents
          @import_run = @job.import_runs.build(import_run_params)
          @import_run.errors.add(:bas_document, "must be an uploaded CSV/XLSX file for this import workflow")
          render :new, status: :unprocessable_entity
          return
        end

        import_run = BasImports::Previewer.new(
          bas_job: @job,
          bas_document: document,
          import_type: import_run_params[:import_type],
          actor_username: current_admin_identifier
        ).call

        if import_run.status == "previewed"
          redirect_to admin_bas_job_import_run_path(@job, import_run), notice: "Import preview created."
        else
          redirect_to admin_bas_job_import_run_path(@job, import_run), alert: "Import preview could not be created."
        end
      rescue ActiveRecord::RecordNotFound
        @documents = importable_documents
        @non_importable_documents = non_importable_documents
        @import_run = @job.import_runs.build(import_run_params)
        @import_run.errors.add(:bas_document, "must be selected")
        render :new, status: :unprocessable_entity
      rescue ActiveRecord::RecordInvalid => e
        @documents = importable_documents
        @non_importable_documents = non_importable_documents
        @import_run = e.record
        render :new, status: :unprocessable_entity
      end

      def show
        @headers = preview_headers
        @import_fields = BasImports::ColumnNormalizer::IMPORT_FIELDS.fetch(@import_run.import_type, [])
        @record_counts = record_counts
      end

      def confirm
        BasImports::Importer.new(
          import_run: @import_run,
          column_mapping: confirm_params[:column_mapping] || {},
          actor_username: current_admin_identifier
        ).call

        if @import_run.reload.status == "imported"
          redirect_to admin_bas_job_import_run_path(@job, @import_run), notice: "Import completed."
        else
          redirect_to admin_bas_job_import_run_path(@job, @import_run), alert: "Import completed with errors."
        end
      end

      def revert
        BasImports::Reverter.new(
          import_run: @import_run,
          actor_username: current_admin_identifier
        ).call
        redirect_to admin_bas_job_import_run_path(@job, @import_run), notice: "Import reverted."
      end

      private

      def set_job
        @job = BasJob.find(params[:job_id])
      end

      def set_import_run
        @import_run = @job.import_runs.includes(:bas_document).find(params[:id])
      end

      def block_locked_job
        return unless @job.locked?

        redirect_to admin_bas_job_import_runs_path(@job), alert: "Locked BAS jobs cannot create, confirm or revert imports."
      end

      def importable_documents
        @job.documents.with_attached_file.ordered.select { |document| bas_spreadsheet_importable_document?(document) }
      end

      def non_importable_documents
        @job.documents.with_attached_file.ordered.reject { |document| bas_spreadsheet_importable_document?(document) }
      end

      def preselect_document
        return if params[:bas_document_id].blank?

        selected_document = @job.documents.with_attached_file.find_by(id: params[:bas_document_id])
        return if selected_document.blank?

        if bas_spreadsheet_importable_document?(selected_document)
          @import_run.bas_document = selected_document
          @import_run.import_type = bas_import_type_for_document(selected_document)
        elsif bas_pdf_bank_statement_document?(selected_document)
          @selected_document_guidance = "PDF bank statements should be converted from the uploaded document row."
        else
          @selected_document_guidance = "Receipts and supporting invoices are stored for review and are not imported as CSV/XLSX files."
        end
      end

      def import_run_params
        params.require(:bas_import_run).permit(:bas_document_id, :import_type)
      end

      def confirm_params
        params.permit(column_mapping: {})
      end

      def preview_headers
        first_row = @import_run.preview_rows.first
        return [] unless first_row.is_a?(Hash)

        first_row.fetch("data", {}).keys
      end

      def record_counts
        {
          bank_transactions: @import_run.bank_transactions.count,
          invoices: @import_run.invoices.count,
          cash_transactions: @import_run.cash_transactions.count,
          payroll_summaries: @import_run.payroll_summaries.count
        }
      end
    end
  end
end
