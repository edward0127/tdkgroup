module Admin
  module Bas
    class DocumentConversionRunsController < Admin::BaseController
      before_action :set_job
      before_action :set_conversion_run, only: [ :show, :confirm_import, :confirm_import_and_match, :download_csv, :abandon ]
      before_action :block_locked_job, only: [ :create, :confirm_import, :confirm_import_and_match, :abandon ]

      def index
        @conversion_runs = @job.document_conversion_runs.includes(:source_bas_document, :bas_import_run).recent
      end

      def show
      end

      def create
        document = @job.documents.find(create_params[:bas_document_id])
        conversion_run = BasPdfBankStatements::ConversionRunner.new(
          bas_job: @job,
          source_bas_document: document,
          actor_username: current_admin_identifier
        ).call

        if conversion_run.status == "previewed"
          redirect_to admin_bas_job_document_conversion_run_path(@job, conversion_run), notice: "PDF bank statement preview created."
        else
          redirect_to admin_bas_job_document_conversion_run_path(@job, conversion_run), alert: "PDF bank statement conversion failed."
        end
      rescue ActiveRecord::RecordNotFound
        redirect_to admin_bas_job_path(@job), alert: "Select a bank statement PDF to convert."
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_bas_job_path(@job), alert: e.record.errors.full_messages.to_sentence
      rescue BasPdfBankStatements::ConversionRunner::LockedJobError => e
        redirect_to admin_bas_job_document_conversion_runs_path(@job), alert: e.message
      end

      def confirm_import
        result = BasPdfBankStatements::ImportRunner.new(
          conversion_run: @conversion_run,
          actor_username: current_admin_identifier
        ).call

        if result.conversion_run.reload.status == "imported"
          redirect_to admin_bas_job_document_conversion_run_path(@job, @conversion_run), notice: "PDF bank statement import completed."
        else
          redirect_to admin_bas_job_document_conversion_run_path(@job, @conversion_run), alert: "PDF bank statement import completed with errors."
        end
      rescue BasPdfBankStatements::ImportRunner::ImportError, BasImports::Importer::LockedJobError => e
        redirect_to admin_bas_job_document_conversion_run_path(@job, @conversion_run), alert: e.message
      end

      def confirm_import_and_match
        result = BasPdfBankStatements::ImportAndMatchRunner.new(
          conversion_run: @conversion_run,
          actor_username: current_admin_identifier
        ).call

        redirect_to admin_bas_job_document_conversion_run_path(@job, @conversion_run),
          notice: "PDF bank statement imported. #{result.proposed_match_count} proposed matches and #{result.open_query_count} open queries after matching."
      rescue BasPdfBankStatements::ImportRunner::ImportError,
             BasImports::Importer::LockedJobError,
             BasMatching::Matcher::LockedJobError,
             BasMatching::QueryGenerator::LockedJobError => e
        redirect_to admin_bas_job_document_conversion_run_path(@job, @conversion_run), alert: e.message
      end

      def download_csv
        csv = BasPdfBankStatements::CsvBuilder.new(rows: @conversion_run.preview_rows).call
        send_data csv,
          filename: "bas-pdf-bank-statement-conversion-#{@conversion_run.id}.csv",
          type: "text/csv; charset=utf-8"
      end

      def abandon
        if @conversion_run.status.in?(%w[imported matched])
          redirect_to admin_bas_job_document_conversion_run_path(@job, @conversion_run), alert: "Imported PDF bank statement conversions cannot be abandoned."
          return
        end

        @conversion_run.update!(status: "abandoned")
        create_abandoned_audit_event
        redirect_to admin_bas_job_document_conversion_run_path(@job, @conversion_run), notice: "PDF bank statement conversion abandoned."
      end

      private

      def set_job
        @job = BasJob.find(params[:job_id])
      end

      def set_conversion_run
        @conversion_run = @job.document_conversion_runs.includes(:source_bas_document, :bas_import_run).find(params[:id])
      end

      def block_locked_job
        return unless @job.locked?

        redirect_to admin_bas_job_document_conversion_runs_path(@job), alert: "Locked BAS jobs cannot change PDF bank statement conversions."
      end

      def create_params
        params.permit(:bas_document_id)
      end

      def create_abandoned_audit_event
        BasAuditEvent.create!(
          bas_job: @job,
          auditable: @conversion_run,
          event_type: "bas_pdf_bank_statement_conversion_abandoned",
          actor_username: current_admin_identifier,
          metadata: {
            source_bas_document_id: @conversion_run.source_bas_document_id,
            bas_document_conversion_run_id: @conversion_run.id,
            bas_import_run_id: @conversion_run.bas_import_run_id,
            row_count: @conversion_run.row_count,
            error_count: @conversion_run.error_count,
            status: @conversion_run.status,
            detected_bank_name: @conversion_run.detected_bank_name
          }.compact
        )
      end
    end
  end
end
