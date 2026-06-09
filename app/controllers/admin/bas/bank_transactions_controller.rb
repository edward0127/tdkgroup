module Admin
  module Bas
    class BankTransactionsController < Admin::BaseController
      before_action :set_job
      before_action :set_bank_transaction, only: [ :show, :ignore, :mark_needs_review, :restore ]
      before_action :block_locked_job, only: [ :ignore, :mark_needs_review, :restore ]

      def index
        @import_runs = @job.import_runs.recent
        @bank_transactions = filtered_scope.limit(250)
      end

      def show
        @matches = @bank_transaction.matches.includes(items: :matchable).recent
        @queries = @job.queries.where(source_type: "BasBankTransaction", source_id: @bank_transaction.id).recent
      end

      def ignore
        update_record_status(@bank_transaction, "ignored", "bas_item_ignored")
        redirect_to admin_bas_job_bank_transactions_path(@job), notice: "Bank transaction ignored."
      end

      def mark_needs_review
        update_record_status(@bank_transaction, "needs_review", "bas_item_needs_review")
        redirect_to admin_bas_job_bank_transactions_path(@job), notice: "Bank transaction marked for review."
      end

      def restore
        update_record_status(@bank_transaction, "imported", "bas_item_restored")
        redirect_to admin_bas_job_bank_transactions_path(@job), notice: "Bank transaction restored."
      end

      private

      def set_job
        @job = BasJob.find(params[:job_id])
      end

      def set_bank_transaction
        @bank_transaction = @job.bank_transactions.find(params[:id])
      end

      def filtered_scope
        scope = @job.bank_transactions.includes(:bas_import_run).recent
        scope = scope.where(status: params[:status]) if params[:status].to_s.in?(BasBankTransaction::STATUS_VALUES)
        scope = scope.where(bas_import_run_id: params[:import_run_id]) if params[:import_run_id].present?
        scope = scope.where(transaction_date: start_date..) if start_date
        scope = scope.where(transaction_date: ..end_date) if end_date

        if params[:q].present?
          query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s)}%"
          scope = scope.where("description LIKE ? OR details LIKE ? OR reference LIKE ?", query, query, query)
        end

        scope
      end

      def start_date
        Date.iso8601(params[:start_date]) if params[:start_date].present?
      rescue Date::Error
        nil
      end

      def end_date
        Date.iso8601(params[:end_date]) if params[:end_date].present?
      rescue Date::Error
        nil
      end

      def update_record_status(record, status, event_type)
        record.update!(status: status, notes: params[:notes].presence || record.notes)
        BasAuditEvent.create!(
          bas_job: @job,
          auditable: record,
          event_type: event_type,
          actor_username: current_admin_identifier,
          metadata: { record_type: record.class.name, record_id: record.id, status: status }
        )
        BasQueries::SourceResolutionSync.new(source: record, actor_username: current_admin_identifier).call
      end

      def block_locked_job
        return unless @job.locked?

        redirect_to admin_bas_job_bank_transactions_path(@job), alert: "Locked BAS jobs cannot have bank transactions changed."
      end
    end
  end
end
