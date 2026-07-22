module Admin
  module Bas
    class TdkCodingRunsController < Admin::BaseController
      class StaleCodingRunError < StandardError; end

      REFERENCE_EXTENSIONS = %w[.csv .xlsx].freeze
      REFERENCE_CONTENT_TYPES = %w[
        text/csv
        application/csv
        application/vnd.ms-excel
        application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
      ].freeze
      REFERENCE_MAX_FILE_SIZE = BasTdk::ReferenceWorkbookReader::MAX_FILE_BYTES
      MAPPING_ROLES = %w[ignore description category amount debit credit gst].freeze
      SINGLETON_MAPPING_ROLES = MAPPING_ROLES - [ "ignore" ]
      CODING_FILTERS = %w[all needs_review prior_match rules manual unclassified].freeze
      CODING_SORTS = Admin::Bas::JobsController::TDK_CODING_SORTS
      CODING_SORT_DIRECTIONS = Admin::Bas::JobsController::TDK_SORT_DIRECTIONS
      ROW_UPDATE_FIELDS = %w[category gst reviewed].freeze

      before_action :set_job
      before_action :ensure_tdk_group_job
      before_action :set_run, only: [ :confirm_mapping, :update_rows, :status ]
      before_action :block_locked_job, except: [ :status ]

      def create
        unless active_target_workbook.present?
          redirect_to admin_bas_job_path(@job), alert: "Process a bank statement before starting Category & GST coding."
          return
        end

        if latest_bank_statement_blocks_coding?
          redirect_to admin_bas_job_path(@job), alert: "Wait for the latest bank statement upload or complete its column mapping before continuing."
          return
        end

        if reference_file.blank?
          redirect_to coding_workflow_path, alert: "Upload the previous quarter Excel or CSV reference file."
          return
        end

        if reference_file_size(reference_file) > REFERENCE_MAX_FILE_SIZE
          error = "Previous-quarter reference is too large. The maximum file size is 25 MB."
          run = create_failed_run(reference_file, error, attach_reference: false)
          create_audit_event(
            run,
            "bas_tdk_coding_reference_upload_failed",
            filename: run.source_filename,
            byte_size: reference_file_size(reference_file)
          )
          redirect_to coding_workflow_path, alert: error
          return
        end

        unless supported_reference_file?(reference_file)
          run = create_failed_run(reference_file, "Previous-quarter reference must be an XLSX or CSV file.")
          create_audit_event(run, "bas_tdk_coding_reference_upload_failed", filename: run.source_filename)
          redirect_to coding_workflow_path, alert: run.processing_errors.to_sentence
          return
        end

        run = create_queued_run(reference_file)
        BasTdkCodingRunProcessingJob.perform_later(
          coding_run_id: run.id,
          actor_username: current_admin_identifier
        )
        create_audit_event(
          run,
          "bas_tdk_coding_run_queued",
          version_number: run.version_number,
          target_workbook_id: run.target_workbook_id,
          filename: run.source_filename
        )

        redirect_to coding_workflow_path, notice: "Previous-quarter reference uploaded. Category & GST suggestions are processing in the background."
      end

      def confirm_mapping
        unless current_mapping_run?
          redirect_to coding_workflow_path, alert: "Only the latest coding reference awaiting mapping can be confirmed."
          return
        end

        mapping_result = validated_mapping
        unless mapping_result.fetch(:valid)
          redirect_to coding_workflow_path(anchor: "tdk-coding-mapping"), alert: mapping_result.fetch(:error)
          return
        end

        @job.with_lock do
          @run.lock!
          unless current_mapping_run_fresh?
            redirect_to coding_workflow_path, alert: "A newer coding reference exists. Review the latest upload instead."
            return
          end

          @run.update!(
            status: "queued",
            column_mapping: mapping_result.fetch(:mapping),
            header_row_number: mapping_result.fetch(:header_row_number),
            data_start_row: mapping_result.fetch(:data_start_row),
            row_errors: [],
            requested_by: current_admin_identifier,
            processing_started_at: nil,
            processing_finished_at: nil,
            processed_at: nil,
            metadata: @run.metadata.to_h.merge(
              "column_mapping_override" => mapping_result.fetch(:mapping).merge(
                "header_row_number" => mapping_result.fetch(:header_row_number),
                "data_start_row" => mapping_result.fetch(:data_start_row)
              )
            )
          )
        end

        BasTdkCodingRunProcessingJob.perform_later(
          coding_run_id: @run.id,
          actor_username: current_admin_identifier
        )
        create_audit_event(
          @run,
          "bas_tdk_coding_column_mapping_confirmed",
          version_number: @run.version_number,
          mapping: mapping_result.fetch(:mapping)
        )

        redirect_to coding_workflow_path, notice: "Reference column mapping confirmed. Category & GST suggestions are processing."
      end

      def update_rows
        unless active_processed_run?(@run)
          redirect_to coding_workflow_path, alert: "Only the active processed coding review can be edited."
          return
        end

        submitted = coding_row_params
        codings = @run.row_codings.includes(:workbook_row).where(id: submitted.keys).index_by { |coding| coding.id.to_s }
        invalid = invalid_gst_update(submitted, codings)
        if invalid.present?
          redirect_to coding_workflow_path(coding_redirect_params), alert: invalid_gst_message(invalid)
          return
        end

        updated_count = 0
        content_changed = false
        now = Time.current

        BasTdkRowCoding.transaction do
          @run.lock!
          @run.target_workbook.lock!
          raise StaleCodingRunError unless active_processed_run_fresh?(@run)

          submitted.each do |coding_id, submitted_values|
            coding = codings[coding_id.to_s]
            next if coding.blank?

            result = update_coding_row(coding, submitted_values, now: now)
            next unless result.fetch(:touched)

            updated_count += 1
            content_changed ||= result.fetch(:content_changed)
          end

          refresh_run_review_counts!
        end

      rescue StaleCodingRunError
        redirect_to coding_workflow_path, alert: "A newer coding review is now active. Your stale page was not saved."
      else
        @run.target_workbook.invalidate_export! if content_changed
        create_audit_event(
          @run,
          "bas_tdk_coding_rows_updated",
          version_number: @run.version_number,
          updated_count: updated_count,
          reviewed_count: @run.reviewed_count
        )

        redirect_to coding_workflow_path(coding_redirect_params), notice: "Saved #{updated_count} coding review rows."
      end

      def status
        render json: status_payload(@run)
      end

      private

      def set_job
        @job = BasJob.find(params[:job_id])
      end

      def ensure_tdk_group_job
        return if @job.tdk_group_workflow?

        redirect_to admin_bas_job_path(@job), alert: "Category & GST coding is only available for TDK Group BAS workflow jobs."
      end

      def set_run
        @run = @job.tdk_coding_runs.find(params[:id])
      end

      def block_locked_job
        return unless @job.locked?

        redirect_to coding_workflow_path, alert: "Locked BAS jobs cannot change Category & GST coding."
      end

      def reference_file
        params.dig(:tdk_coding_run, :reference_file)
      end

      def active_target_workbook
        @active_target_workbook ||= @job.tdk_workbooks.active_processed.first
      end

      def latest_bank_statement_blocks_coding?
        latest = @job.tdk_workbooks.recent.first
        latest.present? && latest.id != active_target_workbook&.id && latest.status.in?(%w[queued processing needs_mapping])
      end

      def supported_reference_file?(file)
        extension = File.extname(source_filename(file)).downcase
        REFERENCE_EXTENSIONS.include?(extension) &&
          (file.content_type.to_s.blank? || REFERENCE_CONTENT_TYPES.include?(file.content_type.to_s))
      end

      def create_queued_run(file)
        @job.with_lock do
          run = @job.tdk_coding_runs.create!(
            target_workbook: active_target_workbook,
            version_number: next_version_number,
            status: "queued",
            source_filename: source_filename(file),
            requested_by: current_admin_identifier,
            metadata: reference_metadata(file)
          )
          run.reference_file.attach(file)
          run
        end
      end

      def create_failed_run(file, error, attach_reference: true)
        @job.with_lock do
          run = @job.tdk_coding_runs.create!(
            target_workbook: active_target_workbook,
            version_number: next_version_number,
            status: "failed",
            source_filename: source_filename(file),
            requested_by: current_admin_identifier,
            row_errors: [ error ],
            processing_finished_at: Time.current,
            metadata: reference_metadata(file)
          )
          run.reference_file.attach(file) if attach_reference
          run
        end
      end

      def next_version_number
        @job.tdk_coding_runs.maximum(:version_number).to_i + 1
      end

      def source_filename(file)
        file&.original_filename.to_s.presence || "previous-quarter-reference"
      end

      def reference_file_size(file)
        file.respond_to?(:size) ? file.size.to_i : file.tempfile.size.to_i
      end

      def reference_metadata(file)
        {
          "content_type" => file.content_type.to_s,
          "byte_size" => reference_file_size(file),
          "target_workbook_version" => active_target_workbook&.version_number
        }
      end

      def current_mapping_run?
        return false unless @run.needs_mapping?
        return false unless @run.target_workbook_id == active_target_workbook&.id

        @job.tdk_coding_runs.recent.first&.id == @run.id
      end

      def current_mapping_run_fresh?
        return false unless @run.needs_mapping?
        active_workbook = @job.tdk_workbooks.active_processed.first
        return false unless active_workbook&.id == @run.target_workbook_id

        BasTdkCodingRun.where(bas_job_id: @job.id).recent.first&.id == @run.id
      end

      def validated_mapping
        raw = params.fetch(:coding_mapping, {})
        columns = raw.fetch(:columns, {})
        columns = columns.to_unsafe_h if columns.respond_to?(:to_unsafe_h)
        detection = @run.metadata.fetch("column_detection", {})
        allowed_indices = Array(detection["columns"]).filter_map do |column|
          source_column = column["source_column"] || column["index"]
          source_column = Integer(source_column, exception: false)
          source_column == 0 ? 1 : source_column
        end
        role_to_index = {}
        used_indices = []

        columns.each do |index_value, role_value|
          index = Integer(index_value, exception: false)
          role = role_value.to_s
          next if role == "ignore"
          return invalid_mapping("Choose a valid role for every mapped column.") unless index.present? && MAPPING_ROLES.include?(role)
          return invalid_mapping("The #{role.humanize} role can only be assigned once.") if role_to_index.key?(role)
          return invalid_mapping("The selected source column is no longer available.") if allowed_indices.any? && !allowed_indices.include?(index)
          return invalid_mapping("Each source column can only be used once.") if used_indices.include?(index)

          role_to_index[role] = index
          used_indices << index
        end

        return invalid_mapping("Map exactly one Description column.") unless role_to_index.key?("description")
        return invalid_mapping("Map exactly one Category column.") unless role_to_index.key?("category")

        direct_amount = role_to_index.key?("amount")
        split_amount = role_to_index.key?("debit") && role_to_index.key?("credit")
        if direct_amount == split_amount
          return invalid_mapping("Map either one Amount column or both Debit and Credit columns.")
        end
        if direct_amount && (role_to_index.key?("debit") || role_to_index.key?("credit"))
          return invalid_mapping("Amount cannot be combined with Debit or Credit columns.")
        end
        if !direct_amount && (role_to_index.key?("debit") ^ role_to_index.key?("credit"))
          return invalid_mapping("Map both Debit and Credit columns when the amount is split.")
        end

        header_row = integer_mapping_value(raw[:header_row_number] || detection["header_row_number"], minimum: 1)
        data_start_row = integer_mapping_value(raw[:data_start_row] || detection["data_start_row"], minimum: 1)
        return invalid_mapping("Choose valid header and data-start rows.") if header_row.blank? || data_start_row.blank? || data_start_row <= header_row

        {
          valid: true,
          mapping: role_to_index,
          header_row_number: header_row,
          data_start_row: data_start_row
        }
      end

      def integer_mapping_value(value, minimum:)
        integer = Integer(value, exception: false)
        integer if integer.present? && integer >= minimum
      end

      def invalid_mapping(message)
        { valid: false, error: message }
      end

      def active_processed_run?(run)
        return false unless run.processed?
        return false unless run.target_workbook_id == active_target_workbook&.id

        @job.tdk_coding_runs.where(target_workbook: active_target_workbook).processed.recent.first&.id == run.id
      end

      def active_processed_run_fresh?(run)
        active_workbook = @job.tdk_workbooks.active_processed.first
        return false unless active_workbook&.id == run.target_workbook_id

        BasTdkCodingRun.where(target_workbook_id: active_workbook.id).processed.recent.first&.id == run.id
      end

      def coding_row_params
        rows = params.fetch(:codings, {})
        rows = rows.to_unsafe_h if rows.respond_to?(:to_unsafe_h)
        rows.transform_values { |values| values.to_h.slice(*ROW_UPDATE_FIELDS) }
      end

      def invalid_gst_update(submitted, codings)
        submitted.each do |coding_id, values|
          coding = codings[coding_id.to_s]
          next if coding.blank? || !values.key?("gst")
          next if BasTdk::WorkbookValues.valid_amount_input?(values["gst"])

          return { coding: coding, value: values["gst"] }
        end
        nil
      end

      def invalid_gst_message(invalid)
        row = invalid.fetch(:coding).workbook_row
        row_number = row.source_row_number.presence || row.position
        "GST contains an invalid number on row #{row_number}: #{invalid.fetch(:value)}"
      end

      def update_coding_row(coding, submitted_values, now:)
        attributes = {}
        row_updates = {}
        content_changed = false
        review_requested = ActiveModel::Type::Boolean.new.cast(submitted_values["reviewed"])
        was_reviewed = coding.reviewed?

        if submitted_values.key?("category")
          category = submitted_values["category"].to_s.strip
          if category != coding.suggested_category.to_s
            content_changed = true
            row_updates["Category"] = category
            attributes.merge!(
              suggested_category: category.presence,
              category_source: category.present? ? "manual" : "unmatched",
              category_review_required: category.blank?
            )
          end
        end

        if submitted_values.key?("gst")
          gst = BasTdk::WorkbookValues.parse_amount(submitted_values["gst"])
          if gst != coding.suggested_gst_amount
            content_changed = true
            row_updates["GST"] = gst.present? ? BasTdk::WorkbookValues.amount_input_value(gst) : ""
            attributes.merge!(
              suggested_gst_amount: gst,
              gst_source: gst.present? ? "manual" : "unmatched",
              gst_review_required: gst.blank?,
              gst_treatment: manual_gst_treatment(gst)
            )
          end
        end

        if review_requested
          attributes[:category_review_required] = false
          attributes[:gst_review_required] = false
        elsif was_reviewed
          attributes[:category_review_required] = true
          attributes[:gst_review_required] = true
        end

        review_state_changed = review_requested != was_reviewed
        touched = content_changed || review_state_changed
        return { touched: false, content_changed: false } unless touched

        category_warning = attributes.fetch(:category_review_required, coding.category_review_required)
        gst_warning = attributes.fetch(:gst_review_required, coding.gst_review_required)
        attributes[:review_status] = if category_warning || gst_warning
          "needs_review"
        elsif content_changed
          "edited"
        else
          "accepted"
        end
        if attributes[:review_status].in?(%w[accepted edited])
          attributes[:reviewed_by] = current_admin_identifier
          attributes[:reviewed_at] = now
        else
          attributes[:reviewed_by] = nil
          attributes[:reviewed_at] = nil
        end
        coding.update!(attributes)

        if row_updates.any?
          workbook_row = coding.workbook_row
          workbook_row.update!(row_data: workbook_row.row_data.deep_dup.merge(row_updates))
        end

        { touched: true, content_changed: content_changed }
      end

      def refresh_run_review_counts!
        @run.update!(
          warning_count: @run.row_codings.requiring_review.count,
          reviewed_count: @run.row_codings.reviewed.count
        )
      end

      def manual_gst_treatment(gst)
        return "unknown" if gst.nil?
        return "no_gst" if gst.zero?

        "taxable"
      end

      def coding_redirect_params
        {
          coding_filter: CODING_FILTERS.include?(params[:coding_filter].to_s) ? params[:coding_filter] : nil,
          coding_page: positive_integer_param(:coding_page),
          coding_per_page: allowed_per_page_param,
          coding_sort: allowed_coding_sort_param,
          coding_direction: allowed_coding_direction_param,
          anchor: "tdk-coding-review"
        }.compact
      end

      def positive_integer_param(key)
        value = params[key].to_i
        value if value.positive?
      end

      def allowed_per_page_param
        value = params[:coding_per_page].to_i
        value if Admin::Bas::JobsController::TDK_ROWS_PER_PAGE_OPTIONS.include?(value)
      end

      def allowed_coding_sort_param
        value = params[:coding_sort].to_s
        value if CODING_SORTS.include?(value)
      end

      def allowed_coding_direction_param
        return if allowed_coding_sort_param.blank?

        value = params[:coding_direction].to_s.downcase
        CODING_SORT_DIRECTIONS.include?(value) ? value : "asc"
      end

      def coding_workflow_path(extra = {})
        admin_bas_job_path(@job, { tdk_step: "coding" }.merge(extra))
      end

      def status_payload(run)
        active = @job.tdk_coding_runs.where(target_workbook: run.target_workbook).processed.recent.first
        {
          id: run.id,
          status: run.status,
          version_number: run.version_number,
          source_filename: run.source_filename,
          processing_errors: run.processing_errors,
          mapping_required: run.needs_mapping?,
          terminal: run.terminal_status?,
          reference_row_count: run.reference_row_count,
          row_count: run.row_count,
          suggestion_count: run.suggestion_count,
          warning_count: run.warning_count,
          reviewed_count: run.reviewed_count,
          active_run_id: active&.id,
          active_run_version: active&.version_number,
          workflow_url: coding_workflow_path
        }
      end

      def create_audit_event(run, event_type, metadata)
        BasAuditEvent.create!(
          bas_job: @job,
          auditable: run,
          event_type: event_type,
          actor_username: current_admin_identifier,
          metadata: metadata.merge(bas_job_id: @job.id, bas_tdk_coding_run_id: run.id)
        )
      end
    end
  end
end
