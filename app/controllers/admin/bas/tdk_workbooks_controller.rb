module Admin
  module Bas
    class TdkWorkbooksController < Admin::BaseController
      TDK_ROWS_PER_PAGE_OPTIONS = [ 10, 25, 50, 100 ].freeze
      TDK_SORT_DIRECTIONS = %w[asc desc].freeze

      before_action :set_job
      before_action :ensure_tdk_group_job
      before_action :set_workbook, only: [ :update_rows, :prepare_download, :download, :status ]
      before_action :block_locked_job, only: [ :create, :update_rows ]

      def create
        if uploaded_file.blank?
          redirect_to admin_bas_job_path(@job), alert: "Upload a bank statement Excel, CSV or PDF file."
          return
        end

        unless supported_upload?(uploaded_file)
          workbook = create_failed_workbook(
            uploaded_file,
            [ BasTdk::BankStatementImporter::SUPPORTED_UPLOAD_ERROR ]
          )
          create_audit_event(
            workbook,
            "bas_tdk_workbook_upload_failed",
            status: workbook.status,
            version_number: workbook.version_number,
            filename: workbook.source_filename
          )
          redirect_to admin_bas_job_path(@job), alert: workbook.processing_errors.to_sentence
          return
        end

        workbook = create_queued_workbook(uploaded_file)
        BasTdkWorkbookProcessingJob.perform_later(
          workbook_id: workbook.id,
          actor_username: current_admin_identifier
        )

        create_audit_event(
          workbook,
          "bas_tdk_workbook_upload_queued",
          bas_tdk_workbook_id: workbook.id,
          status: workbook.status,
          version_number: workbook.version_number,
          filename: workbook.source_filename
        )

        redirect_to admin_bas_job_path(@job), notice: "Bank statement upload queued. Processing will continue in the background."
      end

      def update_rows
        unless @workbook.processed?
          redirect_to admin_bas_job_path(@job), alert: "Only a processed TDK bank statement can be edited."
          return
        end

        invalid_amount = invalid_amount_update
        if invalid_amount.present?
          redirect_to admin_bas_job_path(@job, tdk_table_redirect_params), alert: invalid_amount_message(invalid_amount)
          return
        end

        updated_count = update_visible_rows
        @workbook.invalidate_export! if updated_count.positive?
        create_audit_event(
          @workbook,
          "bas_tdk_workbook_rows_updated",
          bas_tdk_workbook_id: @workbook.id,
          version_number: @workbook.version_number,
          updated_count: updated_count
        )

        redirect_to admin_bas_job_path(@job, tdk_table_redirect_params), notice: "Saved #{updated_count} visible rows."
      end

      def prepare_download
        unless active_processed_workbook?(@workbook)
          redirect_to admin_bas_job_path(@job), alert: "Only the active processed TDK bank statement can be prepared for download."
          return
        end

        queue_export!(@workbook)
        BasTdkWorkbookExportJob.perform_later(
          workbook_id: @workbook.id,
          actor_username: current_admin_identifier
        )
        create_audit_event(
          @workbook,
          "bas_tdk_workbook_export_queued",
          bas_tdk_workbook_id: @workbook.id,
          version_number: @workbook.version_number,
          export_status: @workbook.export_status
        )

        redirect_to admin_bas_job_path(@job), notice: "Excel export queued. Preparation will continue in the background."
      end

      def download
        unless active_processed_workbook?(@workbook)
          redirect_to admin_bas_job_path(@job), alert: "Only the active processed TDK bank statement can be downloaded."
          return
        end

        unless @workbook.export_ready?
          redirect_to admin_bas_job_path(@job), alert: "Excel export is not ready yet. Prepare Excel download first."
          return
        end

        send_data(
          @workbook.export_file.download,
          filename: @workbook.download_filename,
          type: BasTdk::WorkbookExporter::XLSX_CONTENT_TYPE,
          disposition: "attachment"
        )
      end

      def status
        render json: workbook_status_payload(@workbook)
      end

      private

      def set_job
        @job = BasJob.find(params[:job_id])
      end

      def ensure_tdk_group_job
        return if @job.tdk_group_workflow?

        redirect_to admin_bas_job_path(@job), alert: "TDK bank statement uploads are only available for TDK Group BAS workflow jobs."
      end

      def set_workbook
        @workbook = @job.tdk_workbooks.find(params[:id])
      end

      def block_locked_job
        return unless @job.locked?

        redirect_to admin_bas_job_path(@job), alert: "Locked BAS jobs cannot change TDK bank statements."
      end

      def uploaded_file
        params.dig(:tdk_workbook, :file)
      end

      def create_queued_workbook(file)
        @job.with_lock do
          workbook = @job.tdk_workbooks.create!(
            status: "queued",
            source_filename: source_filename(file),
            version_number: next_version_number,
            processed_by: current_admin_identifier,
            metadata: workbook_metadata(file)
          )
          workbook.source_file.attach(file)
          workbook
        end
      end

      def create_failed_workbook(file, errors)
        @job.with_lock do
          workbook = @job.tdk_workbooks.create!(
            status: "failed",
            source_filename: source_filename(file),
            version_number: next_version_number,
            row_count: 0,
            row_errors: errors,
            processed_at: Time.current,
            processing_finished_at: Time.current,
            processed_by: current_admin_identifier,
            metadata: workbook_metadata(file)
          )
          workbook.source_file.attach(file)
          workbook
        end
      end

      def queue_export!(workbook)
        workbook.with_lock do
          workbook.export_file.purge_later if workbook.export_file.attached?
          workbook.update!(
            export_status: "queued",
            export_started_at: nil,
            export_finished_at: nil,
            export_error: nil,
            export_generated_at: nil,
            export_requested_by: current_admin_identifier
          )
        end
      end

      def active_processed_workbook?(workbook)
        workbook.processed? && @job.tdk_workbooks.active_processed.first&.id == workbook.id
      end

      def next_version_number
        @job.tdk_workbooks.maximum(:version_number).to_i + 1
      end

      def source_filename(file)
        file&.original_filename.to_s.presence || "uploaded-bank-statement"
      end

      def supported_upload?(file)
        BasTdk::BankStatementImporter.supported_upload?(
          filename: source_filename(file),
          content_type: file.content_type.to_s
        )
      end

      def workbook_metadata(file)
        {
          "processor" => BasTdk::WorkbookProcessor.name,
          "source_type" => BasTdk::BankStatementImporter.source_type(
            filename: source_filename(file),
            content_type: file.content_type.to_s
          ).to_s
        }
      end

      def update_visible_rows
        allowed_headers = @workbook.processed_headers
        submitted_rows = row_update_params
        updated_count = 0

        BasTdkWorkbookRow.transaction do
          @workbook.rows.where(id: submitted_rows.keys).find_each do |row|
            submitted_data = submitted_rows[row.id.to_s] || {}
            permitted_data = submitted_data.slice(*allowed_headers)
            next if permitted_data.empty?

            row_data = row.row_data.deep_dup
            permitted_data.each do |header, value|
              row_data[header] = normalized_row_update_value(header, value)
            end
            row.update!(row_data: row_data)
            updated_count += 1
          end
        end

        updated_count
      end

      def invalid_amount_update
        amount_headers = @workbook.processed_headers.select { |header| BasTdk::WorkbookValues.amount_header?(header) }
        return if amount_headers.empty?

        allowed_headers = @workbook.processed_headers
        submitted_rows = row_update_params
        rows_by_id = @workbook.rows.where(id: submitted_rows.keys).index_by { |row| row.id.to_s }

        submitted_rows.each do |row_id, submitted_data|
          row = rows_by_id[row_id.to_s]
          next if row.blank?

          permitted_data = submitted_data.slice(*allowed_headers)
          amount_headers.each do |header|
            next unless permitted_data.key?(header)

            value = permitted_data[header].to_s
            next if BasTdk::WorkbookValues.valid_amount_input?(value)

            return { header: header, value: value, row: row }
          end
        end

        nil
      end

      def invalid_amount_message(invalid_amount)
        header = invalid_amount.fetch(:header)
        value = invalid_amount.fetch(:value)
        row = invalid_amount.fetch(:row)
        row_label = row.source_row_number.presence || row.position

        "#{header} contains an invalid number on row #{row_label}: #{value}"
      end

      def normalized_row_update_value(header, value)
        return BasTdk::WorkbookValues.clean_excel_decimal_noise(value) unless BasTdk::WorkbookValues.amount_header?(header)
        return "" if value.to_s.strip.blank?

        BasTdk::WorkbookValues.amount_input_value(value)
      end

      def row_update_params
        params.fetch(:rows, {}).to_unsafe_h
      end

      def page_param
        page = params[:page].to_i
        page.positive? ? page : 1
      end

      def per_page_param
        per_page = params[:per_page].to_i
        return per_page if TDK_ROWS_PER_PAGE_OPTIONS.include?(per_page)

        nil
      end

      def sort_param
        sort = params[:sort].to_s
        return sort if (@workbook.processed_headers + [ "source_row" ]).include?(sort)

        nil
      end

      def direction_param
        direction = params[:direction].to_s.downcase
        return direction if TDK_SORT_DIRECTIONS.include?(direction)

        nil
      end

      def tdk_table_redirect_params
        sort = sort_param
        {
          page: page_param,
          per_page: per_page_param,
          sort: sort,
          direction: sort.present? ? direction_param : nil,
          show_blank_optional_columns: params[:show_blank_optional_columns].to_s == "1" ? "1" : nil
        }.compact
      end

      def workbook_status_payload(workbook)
        active = @job.tdk_workbooks.active_processed.first
        {
          id: workbook.id,
          status: workbook.status,
          version_number: workbook.version_number,
          source_filename: workbook.source_filename,
          row_count: workbook.row_count,
          processing_errors: workbook.processing_errors,
          processing_started_at: workbook.processing_started_at&.iso8601,
          processed_at: workbook.processed_at&.iso8601,
          updated_at: workbook.updated_at&.iso8601,
          active_workbook_id: active&.id,
          active_workbook_version: active&.version_number,
          active_source_filename: active&.source_filename,
          active_table_url: active.present? ? admin_bas_job_path(@job) : nil,
          prepare_download_url: active.present? ? prepare_download_admin_bas_job_tdk_workbook_path(@job, active) : nil,
          download_url: active&.export_ready? ? download_admin_bas_job_tdk_workbook_path(@job, active) : nil,
          export_status: active&.export_status,
          export_error: active&.export_error,
          export_generated_at: active&.export_generated_at&.iso8601
        }
      end

      def create_audit_event(workbook, event_type, metadata)
        BasAuditEvent.create!(
          bas_job: @job,
          auditable: workbook || @job,
          event_type: event_type,
          actor_username: current_admin_identifier,
          metadata: metadata.merge(bas_job_id: @job.id)
        )
      end
    end
  end
end
