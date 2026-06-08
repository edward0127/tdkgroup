module Admin
  module Bas
    class MatchesController < Admin::BaseController
      before_action :set_job
      before_action :set_match, only: [ :show, :accept, :reject, :mark_needs_review ]
      before_action :block_locked_job, only: [ :new, :create, :accept, :reject, :mark_needs_review ]

      def index
        @matches = @job.matches.includes(items: :matchable).recent
        @matching_review_open_count = matching_review_open_count
        @open_queries_count = @job.queries.open_items.count
      end

      def show
      end

      def new
        @match = @job.matches.build(match_type: "manual", status: "accepted")
        set_manual_options
      end

      def create
        @match = @job.matches.build(
          match_type: "manual",
          status: "accepted",
          matched_amount: manual_match_params[:matched_amount],
          notes: manual_match_params[:notes],
          explanation: "Manual admin match",
          created_by_rule: "manual",
          accepted_at: Time.current,
          accepted_by: current_admin_identifier
        )

        attach_manual_match_items!
        if @match.errors.any?
          set_manual_options
          render :new, status: :unprocessable_entity
        elsif @match.save
          update_matched_item_statuses(@match)
          sync_resolved_source_queries(@match)
          create_match_audit_event("bas_manual_match_created", @match)
          redirect_to admin_bas_job_match_path(@job, @match), notice: "Manual match created."
        else
          set_manual_options
          render :new, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotFound
        @match.errors.add(:base, "Selected records must belong to this BAS job")
        set_manual_options
        render :new, status: :unprocessable_entity
      end

      def accept
        @match.update!(
          status: "accepted",
          accepted_at: Time.current,
          accepted_by: current_admin_identifier
        )
        update_matched_item_statuses(@match)
        sync_resolved_source_queries(@match)
        create_match_audit_event("bas_match_accepted", @match)
        redirect_to return_path, notice: accepted_flash
      end

      def reject
        @match.update!(
          status: "rejected",
          rejected_at: Time.current,
          rejected_by: current_admin_identifier
        )
        create_match_audit_event("bas_match_rejected", @match)
        redirect_to return_path, notice: rejected_flash
      end

      def mark_needs_review
        @match.update!(status: "needs_review")
        @match.items.each { |item| item.matchable.update!(status: "needs_review") if item.matchable.respond_to?(:status) }
        create_match_audit_event("bas_match_needs_review", @match)
        redirect_to return_path, notice: "Match marked as needs review."
      end

      private

      def set_job
        @job = BasJob.find(params[:job_id])
      end

      def set_match
        @match = @job.matches.includes(items: :matchable).find(params[:id])
      end

      def set_manual_options
        @invoices = @job.invoices.where.not(status: %w[matched ignored]).recent
        @bank_transactions = @job.bank_transactions.where.not(status: %w[matched ignored]).recent
        @cash_transactions = @job.cash_transactions.where.not(status: %w[ignored]).recent
      end

      def manual_match_params
        params.require(:bas_match).permit(:matched_amount, :notes, invoice_ids: [])
      end

      def attach_manual_match_items!
        invoice_ids = Array(manual_match_params[:invoice_ids]).compact_blank
        invoice_ids.each do |invoice_id|
          invoice = @job.invoices.find(invoice_id)
          @match.items.build(matchable: invoice, amount: invoice.total_amount)
        end

        if params.dig(:bas_match, :bank_transaction_id).present?
          transaction = @job.bank_transactions.find(params.dig(:bas_match, :bank_transaction_id))
          @match.items.build(matchable: transaction, amount: transaction.amount)
        elsif params.dig(:bas_match, :cash_transaction_id).present?
          transaction = @job.cash_transactions.find(params.dig(:bas_match, :cash_transaction_id))
          @match.items.build(matchable: transaction, amount: transaction.total_amount)
        else
          @match.errors.add(:base, "Select a bank or cash transaction")
        end

        @match.errors.add(:base, "Select at least one invoice") if invoice_ids.blank?
      end

      def update_matched_item_statuses(match)
        match.items.each do |item|
          next unless item.matchable.respond_to?(:status)
          next unless item.matchable.class.const_defined?(:STATUS_VALUES)
          next unless item.matchable.class::STATUS_VALUES.include?("matched")

          item.matchable.update!(status: "matched")
        end
      end

      def sync_resolved_source_queries(match)
        match.items.each do |item|
          BasQueries::SourceResolutionSync.new(
            source: item.matchable,
            actor_username: current_admin_identifier
          ).call
        end
      end

      def create_match_audit_event(event_type, match)
        BasAuditEvent.create!(
          bas_job: @job,
          auditable: match,
          event_type: event_type,
          actor_username: current_admin_identifier,
          metadata: {
            bas_match_id: match.id,
            match_type: match.match_type,
            status: match.status,
            item_count: match.items.size
          }
        )
      end

      def block_locked_job
        return unless @job.locked?

        redirect_to admin_bas_job_matches_path(@job), alert: "Locked BAS jobs cannot have matches changed."
      end

      def return_path
        case params[:return_to]
        when "matches"
          admin_bas_job_matches_path(@job)
        when "workflow"
          admin_bas_job_matching_path(@job)
        else
          admin_bas_job_matching_path(@job)
        end
      end

      def matching_review_open_count
        @job.matches.proposed.count + @job.matches.needs_review.count
      end

      def accepted_flash
        remaining = matching_review_open_count
        return "Match accepted. No proposed/needs-review matches remaining." if remaining.zero?

        "Match accepted. #{remaining} proposed/needs-review matches remaining."
      end

      def rejected_flash
        remaining = matching_review_open_count
        return "Match rejected. Generate client queries is now available." if remaining.zero?

        "Match rejected. Review #{remaining} proposed/needs-review matches before generating client queries."
      end
    end
  end
end
