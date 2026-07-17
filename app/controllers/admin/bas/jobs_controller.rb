module Admin
  module Bas
    class JobsController < Admin::BaseController
      before_action :set_job, only: [ :show, :edit, :update, :destroy ]
      before_action :set_clients, only: [ :new, :create, :edit, :update ]
      BAS_WORKSPACE_TABS = %w[overview documents matching report audit ai].freeze
      TDK_ROWS_PER_PAGE_OPTIONS = [ 10, 25, 50, 100 ].freeze
      TDK_SORT_DIRECTIONS = %w[asc desc].freeze
      TDK_CODING_FILTERS = %w[all needs_review prior_match rules manual unclassified].freeze

      def index
        @jobs = BasJob.includes(:bas_client, :report_snapshots).order(period_end: :desc, id: :desc)
      end

      def show
        if @job.tdk_group_workflow?
          prepare_tdk_workflow
          return
        end

        prepare_standard_workspace
      end

      def new
        @job = BasJob.new(
          bas_client_id: params[:bas_client_id],
          workflow_type: initial_workflow_type
        )
      end

      def create
        @job = BasJob.new(job_params)

        if @job.save
          create_job_audit_event("bas_job_created", changed_fields: [])
          redirect_to admin_bas_job_path(@job), notice: "BAS job created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        previous_status = @job.status
        @job.assign_attributes(job_params)
        changed_fields = @job.changed - %w[internal_notes approved_by locked_by]

        if @job.save
          create_job_audit_event("bas_job_updated", changed_fields: changed_fields)
          if previous_status != @job.status
            create_job_audit_event(
              "bas_job_status_changed",
              previous_status: previous_status,
              status: @job.status
            )
          end
          redirect_to admin_bas_job_path(@job), notice: "BAS job updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        client = @job.bas_client

        unless @job.cleanup_deletable?
          redirect_to admin_bas_job_path(@job), alert: BasJob::CLEANUP_DELETE_BLOCKED_MESSAGE
          return
        end

        if @job.destroy
          redirect_to admin_bas_client_path(client), notice: "BAS job was deleted."
        else
          redirect_to admin_bas_job_path(@job), alert: @job.errors.full_messages.to_sentence.presence || BasJob::CLEANUP_DELETE_BLOCKED_MESSAGE
        end
      end

      private

      def set_job
        @job = BasJob.includes(:bas_client).find(params[:id])
      end

      def set_clients
        @clients = BasClient.ordered
      end

      def initial_workflow_type
        workflow_type = params[:workflow_type].to_s
        return workflow_type if BasJob::WORKFLOW_TYPE_VALUES.include?(workflow_type)

        "standard"
      end

      def prepare_standard_workspace
        @documents = @job.documents.with_attached_file.includes(:import_runs, :conversion_runs).ordered
        @documents_by_type = @documents.group_by(&:document_type)
        @import_runs = @job.import_runs.includes(:bas_document).recent.limit(6)
        @bank_transactions = @job.bank_transactions.recent.limit(8)
        @invoices = @job.invoices.recent.limit(8)
        @cash_transactions = @job.cash_transactions.recent.limit(8)
        @payroll_summaries = @job.payroll_summaries.recent.limit(8)
        @proposed_matches_count = @job.matches.proposed.count
        @needs_review_matches_count = @job.matches.needs_review.count
        @accepted_matches_count = @job.matches.accepted.count
        @rejected_matches_count = @job.matches.rejected.count
        @total_matches_count = @job.matches.count
        @unmatched_bank_transactions_count = @job.bank_transactions.unmatched.count
        @unmatched_invoices_count = @job.invoices.unmatched.count
        @unmatched_cash_transactions_count = @job.cash_transactions.unmatched.count
        @imported_records_count = @job.bank_transactions.count + @job.invoices.count + @job.cash_transactions.count + @job.payroll_summaries.count
        @import_error_count = @job.import_runs.sum(:error_count)
        @failed_import_runs_count = @job.import_runs.where(status: "failed").count
        @latest_report_snapshot = @job.report_snapshots.recent.first
        @report_snapshots = @job.report_snapshots.recent.limit(5)
        @approval_blockers_count = BasReports::ApprovalValidator.new(bas_job: @job).call.size
        @ai_config = BasAi::Config.current
        @workspace_tabs = workspace_tabs
        @active_tab = active_workspace_tab
        @ai_readiness = BasAi::ReadinessChecker.new(bas_job: @job)
        @ai_runs = @job.ai_extraction_runs.recent.limit(5)
        @ai_suggestions_count = @job.ai_suggestions.proposed.count
        @open_queries = @job.queries.open_items.recent
        @open_queries_count = @open_queries.count
        @queries_count = @job.queries.count
        @audit_events = @job.audit_events.recent.limit(12)
        @next_step = Admin::Bas::JobNextStepPresenter.new(job: @job)
      end

      def prepare_tdk_workflow
        @latest_tdk_workbook = @job.tdk_workbooks.recent.first
        @latest_tdk_workbook_operation = @latest_tdk_workbook
        @active_tdk_workbook = @job.tdk_workbooks.active_processed.first
        @tdk_summary_workbook = @active_tdk_workbook
        prepare_tdk_step_state
        prepare_tdk_coding_workflow

        if @tdk_step == "coding"
          prepare_empty_tdk_statement_rows
        else
          prepare_tdk_statement_rows
        end
      end

      def prepare_tdk_statement_rows
        @tdk_per_page_options = TDK_ROWS_PER_PAGE_OPTIONS
        @tdk_rows_per_page = tdk_rows_per_page
        @tdk_sort = tdk_sort_param
        @tdk_direction = tdk_sort_direction
        sorted_rows = tdk_sorted_workbook_rows
        @tdk_total_rows = sorted_rows.size
        @tdk_total_pages = [ (@tdk_total_rows.to_f / @tdk_rows_per_page).ceil, 1 ].max
        @tdk_page = params.fetch(:page, 1).to_i
        @tdk_page = 1 if @tdk_page < 1
        @tdk_page = @tdk_total_pages if @tdk_page > @tdk_total_pages
        @tdk_row_start = @tdk_total_rows.positive? ? ((@tdk_page - 1) * @tdk_rows_per_page) + 1 : 0
        @tdk_row_end = [ @tdk_page * @tdk_rows_per_page, @tdk_total_rows ].min
        @tdk_workbook_rows = sorted_rows.slice((@tdk_page - 1) * @tdk_rows_per_page, @tdk_rows_per_page) || []
      end

      def prepare_empty_tdk_statement_rows
        @tdk_per_page_options = TDK_ROWS_PER_PAGE_OPTIONS
        @tdk_rows_per_page = tdk_rows_per_page
        @tdk_sort = "source_row"
        @tdk_sort_param_valid = false
        @tdk_direction = "asc"
        @tdk_total_rows = 0
        @tdk_total_pages = 1
        @tdk_page = 1
        @tdk_row_start = 0
        @tdk_row_end = 0
        @tdk_workbook_rows = []
      end

      def prepare_tdk_step_state
        @tdk_step_two_blocked_reason = tdk_step_two_blocked_reason
        @tdk_step_two_available = @active_tdk_workbook.present? && @tdk_step_two_blocked_reason.blank?
        requested_step = params[:tdk_step].to_s
        @tdk_step = requested_step == "coding" && @tdk_step_two_available ? "coding" : "statement"
      end

      def tdk_step_two_blocked_reason
        return if @active_tdk_workbook.blank?
        return unless @latest_tdk_workbook_operation.present? && @latest_tdk_workbook_operation.id != @active_tdk_workbook.id

        case @latest_tdk_workbook_operation.status
        when "queued", "processing"
          "Wait for the latest bank statement upload to finish before continuing."
        when "needs_mapping"
          "Confirm the latest bank statement column mapping before continuing."
        end
      end

      def prepare_tdk_coding_workflow
        coding_runs = @job.tdk_coding_runs
        coding_runs = coding_runs.where(target_workbook: @active_tdk_workbook) if @active_tdk_workbook.present?
        @latest_tdk_coding_run = coding_runs.recent.first
        @active_tdk_coding_run = coding_runs.processed.recent.first
        @tdk_step_two_completed = @active_tdk_coding_run.present? &&
          @latest_tdk_coding_run&.id == @active_tdk_coding_run.id &&
          @active_tdk_coding_run.row_count.positive? &&
          @active_tdk_coding_run.warning_count.zero?

        if @tdk_step == "coding"
          prepare_tdk_coding_rows
        else
          prepare_empty_tdk_coding_rows
        end
      end

      def prepare_tdk_coding_rows
        @tdk_coding_filter = TDK_CODING_FILTERS.include?(params[:coding_filter].to_s) ? params[:coding_filter].to_s : "all"
        @tdk_coding_per_page = coding_rows_per_page
        base_scope = if @active_tdk_coding_run.present?
          @active_tdk_coding_run.row_codings.joins(:workbook_row)
        else
          BasTdkRowCoding.none.joins(:workbook_row)
        end

        @tdk_coding_filter_counts = TDK_CODING_FILTERS.index_with do |filter|
          filter_tdk_codings(base_scope, filter).count
        end
        filtered_scope = filter_tdk_codings(base_scope, @tdk_coding_filter)
        @tdk_coding_total_rows = @tdk_coding_filter_counts.fetch(@tdk_coding_filter)
        @tdk_coding_total_pages = [ (@tdk_coding_total_rows.to_f / @tdk_coding_per_page).ceil, 1 ].max
        @tdk_coding_page = params.fetch(:coding_page, 1).to_i.clamp(1, @tdk_coding_total_pages)
        @tdk_coding_row_start = @tdk_coding_total_rows.positive? ? ((@tdk_coding_page - 1) * @tdk_coding_per_page) + 1 : 0
        @tdk_coding_row_end = [ @tdk_coding_page * @tdk_coding_per_page, @tdk_coding_total_rows ].min
        @tdk_row_codings = filtered_scope
          .order("bas_tdk_workbook_rows.position ASC", "bas_tdk_row_codings.id ASC")
          .offset((@tdk_coding_page - 1) * @tdk_coding_per_page)
          .limit(@tdk_coding_per_page)
          .includes(:workbook_row)
          .to_a
      end

      def prepare_empty_tdk_coding_rows
        @tdk_coding_filter = "all"
        @tdk_coding_per_page = coding_rows_per_page
        @tdk_coding_filter_counts = TDK_CODING_FILTERS.index_with { 0 }
        @tdk_coding_total_rows = 0
        @tdk_coding_total_pages = 1
        @tdk_coding_page = 1
        @tdk_coding_row_start = 0
        @tdk_coding_row_end = 0
        @tdk_row_codings = []
      end

      def coding_rows_per_page
        requested = params[:coding_per_page].to_i
        TDK_ROWS_PER_PAGE_OPTIONS.include?(requested) ? requested : 25
      end

      def filter_tdk_codings(codings, filter)
        case filter
        when "needs_review"
          codings.where(category_review_required: true).or(codings.where(gst_review_required: true))
        when "prior_match"
          sources = %w[previous_quarter_exact previous_quarter_fuzzy]
          codings.where(category_source: sources).or(codings.where(gst_source: sources))
        when "rules"
          codings.where(category_source: "rule").or(codings.where(gst_source: "rule"))
        when "manual"
          codings.where(category_source: "manual").or(codings.where(gst_source: "manual"))
        when "unclassified"
          codings.where(category_source: "unmatched").or(codings.where(gst_source: "unmatched"))
        else
          codings
        end
      end

      def tdk_rows_per_page
        requested = params[:per_page].to_i
        return requested if TDK_ROWS_PER_PAGE_OPTIONS.include?(requested)

        25
      end

      def tdk_sort_param
        requested = params[:sort].to_s
        allowed = @active_tdk_workbook&.processed_headers.to_a + [ "source_row" ]
        @tdk_sort_param_valid = allowed.include?(requested)
        return requested if @tdk_sort_param_valid

        "source_row"
      end

      def tdk_sort_direction
        return "asc" unless @tdk_sort_param_valid

        requested = params[:direction].to_s.downcase
        return requested if TDK_SORT_DIRECTIONS.include?(requested)

        "asc"
      end

      def tdk_sorted_workbook_rows
        return [] if @active_tdk_workbook.blank?

        rows = @active_tdk_workbook.rows.ordered.to_a
        return rows if @tdk_sort.blank? || (@tdk_sort == "source_row" && @tdk_direction == "asc")

        rows.sort { |left, right| compare_tdk_workbook_rows(left, right) }
      end

      def compare_tdk_workbook_rows(left, right)
        left_value = tdk_workbook_sort_value(left)
        right_value = tdk_workbook_sort_value(right)

        blank_result = blank_sort_comparison(left_value, right_value)
        return blank_result unless blank_result.zero?
        return tdk_workbook_source_order_comparison(left, right) if left_value.nil? && right_value.nil?

        result = left_value.fetch(:value) <=> right_value.fetch(:value)
        result ||= 0
        return tdk_workbook_source_order_comparison(left, right) if result.to_i.zero?

        @tdk_direction == "desc" ? -result : result
      end

      def blank_sort_comparison(left_value, right_value)
        left_blank = left_value.nil?
        right_blank = right_value.nil?
        return 0 if left_blank == right_blank

        left_blank ? 1 : -1
      end

      def tdk_workbook_source_order_comparison(left, right)
        (left.source_row_number.to_i <=> right.source_row_number.to_i).nonzero? ||
          (left.position.to_i <=> right.position.to_i).nonzero? ||
          (left.id.to_i <=> right.id.to_i)
      end

      def tdk_workbook_sort_value(row)
        return { value: row.source_row_number.to_i } if @tdk_sort == "source_row"

        raw_value = row.row_data[@tdk_sort]
        return if raw_value.to_s.blank?

        if BasTdk::WorkbookValues.date_header?(@tdk_sort)
          date = BasTdk::WorkbookValues.parse_date(raw_value)
          return date.present? ? { value: date } : nil
        end

        if BasTdk::WorkbookValues.amount_header?(@tdk_sort)
          amount = BasTdk::WorkbookValues.parse_amount(raw_value)
          return amount.present? ? { value: amount } : nil
        end

        { value: BasTdk::WorkbookValues.clean_excel_decimal_noise(raw_value).downcase }
      end

      def workspace_tabs
        tabs = [
          { key: "overview", label: "Overview" },
          { key: "documents", label: "Files & imports" },
          { key: "matching", label: "Matches & queries" },
          { key: "report", label: "Reports" },
          { key: "audit", label: "Audit & admin" }
        ]
        tabs.insert(4, { key: "ai", label: "AI review" }) if @ai_config.ui_enabled?
        tabs
      end

      def active_workspace_tab
        tab = params[:tab].presence || "overview"
        valid_tabs = @workspace_tabs.map { |item| item.fetch(:key) }
        return tab if BAS_WORKSPACE_TABS.include?(tab) && valid_tabs.include?(tab)

        "overview"
      end

      def job_params
        params.require(:bas_job).permit(
          :bas_client_id,
          :period_start,
          :period_end,
          :quarter_label,
          :workflow_type,
          :status,
          :gst_basis,
          :reporting_method,
          :payroll_applicable,
          :cash_transactions_applicable,
          :internal_notes
        )
      end

      def create_job_audit_event(event_type, metadata)
        BasAuditEvent.create!(
          bas_job: @job,
          auditable: @job,
          event_type: event_type,
          actor_username: current_admin_identifier,
          metadata: metadata.merge(bas_job_id: @job.id, bas_client_id: @job.bas_client_id)
        )
      end
    end
  end
end
