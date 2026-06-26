module Admin
  module Bas
    module WorkflowHelper
      SPREADSHEET_IMPORT_TYPE_BY_DOCUMENT_TYPE = {
        "bank_statement" => "bank_statement",
        "invoice_summary" => "invoice_summary",
        "cash_transaction_list" => "cash_transactions",
        "payroll_summary" => "payroll_summary"
      }.freeze

      SUPPORTING_ONLY_DOCUMENT_TYPES = %w[
        receipt
        sales_invoice
        supplier_invoice
        ato_bas_form
        other
      ].freeze

      SPREADSHEET_EXTENSIONS = %w[csv xls xlsx].freeze
      PDF_EXTENSIONS = %w[pdf].freeze

      SPREADSHEET_CONTENT_TYPES = %w[
        text/csv
        application/csv
        application/vnd.ms-excel
        application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
      ].freeze

      PDF_CONTENT_TYPES = %w[application/pdf].freeze

      def bas_workflow_steps(job:, documents_count:, imported_records_count:, proposed_matches_count:, needs_review_matches_count:, open_queries_count:, approval_blockers_count:, latest_report_snapshot:)
        matching_review_count = proposed_matches_count + needs_review_matches_count
        locked = job.locked?

        [
          {
            title: "Step 1: Upload files",
            description: "Upload bank statements, invoice summaries, cash transaction lists, payroll summaries, and supporting receipts.",
            status: bas_workflow_status(locked: locked, completed: documents_count.positive?, action_required: documents_count.zero?),
            action_label: locked ? nil : "Upload source file",
            action_path: locked ? nil : new_admin_bas_job_document_path(job)
          },
          {
            title: "Step 2: Import / convert",
            description: "Import CSV/XLSX files into BAS records, or convert standard bank PDF statements to a reviewable import preview.",
            status: bas_workflow_status(locked: locked, completed: imported_records_count.positive?, action_required: documents_count.positive? && imported_records_count.zero?),
            action_label: locked ? nil : "Import uploaded files",
            action_path: locked ? nil : admin_bas_job_import_runs_path(job)
          },
          {
            title: "Step 3: Match records",
            description: "Create match suggestions and review them before generating client queries.",
            status: bas_workflow_status(locked: locked, completed: imported_records_count.positive? && matching_review_count.zero?, action_required: matching_review_count.positive? || imported_records_count.positive?),
            action_label: locked ? nil : "Review matching",
            action_path: locked ? nil : admin_bas_job_matching_path(job)
          },
          {
            title: "Step 4: Generate client queries",
            description: "Create query list and email draft after match review is complete.",
            status: bas_workflow_status(locked: locked, completed: open_queries_count.positive?, action_required: imported_records_count.positive? && matching_review_count.zero? && open_queries_count.zero?),
            action_label: locked ? nil : "Generate client queries",
            action_path: locked ? nil : admin_bas_job_matching_path(job)
          },
          {
            title: "Step 5: Review BAS report",
            description: "Calculate draft BAS figures and review approval blockers.",
            status: bas_workflow_status(locked: locked, completed: latest_report_snapshot.present? && approval_blockers_count.zero?, action_required: approval_blockers_count.positive? || (imported_records_count.positive? && latest_report_snapshot.blank?)),
            action_label: locked ? nil : "Calculate BAS report",
            action_path: locked ? nil : admin_bas_job_report_path(job)
          },
          {
            title: "Step 6: Snapshot / approve / lock",
            description: "Save the draft report, approve final figures, then lock the job.",
            status: if locked
              "Locked/final"
            elsif latest_report_snapshot&.final?
              "Completed"
            elsif latest_report_snapshot.present?
              "Action required"
            else
              "Waiting"
            end,
            action_label: latest_report_snapshot.present? ? "Open latest snapshot" : "Calculate BAS report",
            action_path: latest_report_snapshot.present? ? admin_bas_job_report_snapshot_path(job, latest_report_snapshot) : admin_bas_job_report_path(job)
          }
        ]
      end

      def bas_client_heading_name(client)
        client.primary_name
      end

      def bas_client_metadata_lines(client, job: nil, include_status: false)
        lines = []
        trading_name = client.trading_name.to_s.squish

        if trading_name.present? && !trading_name.casecmp?(client.primary_name)
          lines << "Trading name: #{trading_name}"
        end

        lines << "ABN: #{client.formatted_abn}" if client.formatted_abn.present?
        lines << "Industry: #{client.industry_label}"
        lines << "BAS job: #{job.period_label}" if job.present?
        lines << (client.archived? ? "Archived client" : "Active client") if include_status
        lines
      end

      def bas_job_heading_metadata(job)
        safe_join(
          bas_client_metadata_lines(job.bas_client, job: job).map { |line| content_tag(:p, line) }
        )
      end

      def bas_client_heading_metadata(client, include_status: false)
        safe_join(
          bas_client_metadata_lines(client, include_status: include_status).map { |line| content_tag(:p, line) }
        )
      end

      def bas_job_warning_banners(job)
        banners = []
        edit_path = edit_admin_bas_job_path(job)

        if job.reporting_method == "unknown"
          banners << {
            message: "Reporting method is unknown. Set the reporting method before final approval.",
            action_label: "Edit job",
            action_path: edit_path
          }
        end

        if job.gst_basis == "unknown"
          banners << {
            message: "GST basis is unknown. Set the GST basis before final approval.",
            action_label: "Edit job",
            action_path: edit_path
          }
        end

        if !job.payroll_applicable? && job.payroll_summaries.exists?
          banners << {
            message: "Payroll is marked not applicable, but payroll records exist. Update the job settings or review the imported payroll records before final approval.",
            action_label: "Edit job",
            action_path: edit_path
          }
        end

        if !job.cash_transactions_applicable? && job.cash_transactions.exists?
          banners << {
            message: "Cash transactions are marked not applicable, but cash transaction records exist. Update the job settings or review the imported cash transaction records before final approval.",
            action_label: "Edit job",
            action_path: edit_path
          }
        end

        if job.locked?
          banners << {
            message: "This BAS job is locked. Workflow actions are read-only.",
            action_label: nil,
            action_path: nil
          }
        end

        banners
      end

      def bas_spreadsheet_importable_document?(document)
        SPREADSHEET_IMPORT_TYPE_BY_DOCUMENT_TYPE.key?(document.document_type) && bas_spreadsheet_document?(document)
      end

      def bas_import_type_for_document(document)
        return unless bas_spreadsheet_importable_document?(document)

        SPREADSHEET_IMPORT_TYPE_BY_DOCUMENT_TYPE.fetch(document.document_type)
      end

      def bas_supporting_only_document?(document)
        SUPPORTING_ONLY_DOCUMENT_TYPES.include?(document.document_type)
      end

      def bas_pdf_bank_statement_document?(document)
        document.document_type == "bank_statement" && bas_pdf_document?(document)
      end

      def bas_submit_guard_data(loading_text = nil)
        {
          controller: "submit-guard",
          action: "click->submit-guard#rememberSubmitter submit->submit-guard#submit turbo:submit-start->submit-guard#submitStart turbo:submit-end->submit-guard#submitEnd turbo:before-cache@document->submit-guard#reset"
        }.tap do |data|
          data[:submit_guard_loading_text_value] = loading_text if loading_text.present?
        end
      end

      def bas_submit_guard_form(loading_text = nil, data: {}, **options)
        options.merge(data: data.merge(bas_submit_guard_data(loading_text)))
      end

      def tdk_workbook_rows_form_data
        bas_submit_guard_data("Saving rows").tap do |data|
          data[:controller] = [ data[:controller], "tdk-save-scroll" ].join(" ")
          data[:action] = [ data[:action], "submit->tdk-save-scroll#store" ].join(" ")
        end
      end

      def bas_document_status_label(document)
        return "Stored only - no import needed" if bas_supporting_only_document?(document)
        return bas_pdf_bank_statement_status_label(document) if bas_pdf_bank_statement_document?(document)
        return bas_spreadsheet_status_label(document) if bas_spreadsheet_importable_document?(document)
        return "Needs review" if document.processing_status.in?(%w[failed needs_review])

        "Stored only - no import needed"
      end

      def tdk_workbook_status_class(status)
        case status.to_s
        when "processed"
          "is-success"
        when "failed"
          "is-danger"
        when "queued", "processing"
          "is-working"
        when "superseded"
          "is-muted"
        else
          "is-neutral"
        end
      end

      def tdk_workbook_export_status_label(workbook)
        return "Ready to download" if workbook&.export_ready?

        case workbook&.export_status.to_s
        when "queued", "processing"
          "Preparing Excel download..."
        when "failed"
          "Export failed"
        when "stale"
          "Export needs refresh"
        else
          "Not prepared"
        end
      end

      def tdk_workbook_column_class(header)
        normalized = BasTdk::WorkbookValues.normalize_header(header)
        return "tdk-workbook-col--date" if normalized.include?("date")
        return "tdk-workbook-col--category" if normalized == "category" || normalized.include?("category")
        return "tdk-workbook-col--gst" if normalized == "gst" || normalized.include?("gst")
        return "tdk-workbook-col--balance" if normalized == "balance" || normalized.include?("running balance")
        return "tdk-workbook-col--amount" if normalized.match?(/\b(amount|debit|credit|net|gross|balance|paid)\b/)
        return "tdk-workbook-col--description" if normalized.include?("description")
        return "tdk-workbook-col--details" if normalized.match?(/\b(details|narration|reference|memo)\b/)

        "tdk-workbook-col--medium"
      end

      def tdk_workbook_review_field?(header)
        normalized = BasTdk::WorkbookValues.normalize_header(header)
        normalized == "category" || normalized == "gst"
      end

      def tdk_workbook_date_header?(header)
        BasTdk::WorkbookValues.date_header?(header)
      end

      def tdk_workbook_amount_header?(header)
        BasTdk::WorkbookValues.amount_header?(header)
      end

      def tdk_workbook_date_input_value(value)
        BasTdk::WorkbookValues.iso_date_value(value)
      end

      def tdk_workbook_amount_input_value(value)
        BasTdk::WorkbookValues.amount_input_value(value)
      end

      def tdk_workbook_amount_input_pattern
        BasTdk::WorkbookValues::AMOUNT_INPUT_PATTERN
      end

      def tdk_workbook_amount_input_title
        BasTdk::WorkbookValues::AMOUNT_INPUT_TITLE
      end

      def tdk_workbook_display_value(value)
        BasTdk::WorkbookValues.clean_excel_decimal_noise(value)
      end

      def tdk_workbook_sortable_header?(header)
        key = tdk_workbook_sort_key(header)
        key == "source_row" || @active_tdk_workbook&.processed_headers&.include?(key)
      end

      def tdk_workbook_sort_direction_for(header)
        key = tdk_workbook_sort_key(header)
        return "desc" if @tdk_sort == key && @tdk_direction == "asc"

        "asc"
      end

      def tdk_workbook_sort_link_params(header)
        {
          sort: tdk_workbook_sort_key(header),
          direction: tdk_workbook_sort_direction_for(header),
          page: 1,
          per_page: @tdk_rows_per_page,
          anchor: "tdk-active-table"
        }
      end

      def tdk_workbook_sort_indicator(header)
        return "&#8597;".html_safe unless @tdk_sort == tdk_workbook_sort_key(header)

        @tdk_direction == "desc" ? "&darr;".html_safe : "&uarr;".html_safe
      end

      def tdk_workbook_page_link_params(page)
        {
          page: page,
          per_page: @tdk_rows_per_page,
          sort: @tdk_sort,
          direction: @tdk_direction,
          anchor: "tdk-active-table"
        }.compact
      end

      def tdk_workbook_row_range_label(start_row, end_row, total_rows)
        return "Rows 0 of 0" if total_rows.to_i.zero?

        "Rows #{start_row}-#{end_row} of #{total_rows}"
      end

      def bas_latest_import_run_for_document(document)
        document.import_runs.max_by { |run| [ run.created_at || Time.zone.at(0), run.id || 0 ] }
      end

      def bas_latest_conversion_run_for_document(document)
        document.conversion_runs.max_by { |run| [ run.created_at || Time.zone.at(0), run.id || 0 ] }
      end

      def bas_document_extension(document)
        File.extname(document.safe_filename.to_s).delete_prefix(".").downcase
      end

      def bas_spreadsheet_document?(document)
        SPREADSHEET_CONTENT_TYPES.include?(bas_document_content_type(document)) ||
          SPREADSHEET_EXTENSIONS.include?(bas_document_extension(document))
      end

      def bas_pdf_document?(document)
        PDF_CONTENT_TYPES.include?(bas_document_content_type(document)) ||
          PDF_EXTENSIONS.include?(bas_document_extension(document))
      end

      private

      def bas_workflow_status(locked:, completed:, action_required:)
        return "Locked/final" if locked
        return "Completed" if completed
        return "Action required" if action_required

        "Waiting"
      end

      def bas_pdf_bank_statement_status_label(document)
        case bas_latest_conversion_run_for_document(document)&.status
        when "failed"
          "Needs review"
        when "previewed"
          "PDF preview waiting confirmation"
        when "imported", "matched"
          "Imported"
        else
          "Uploaded - ready to convert"
        end
      end

      def bas_spreadsheet_status_label(document)
        case bas_latest_import_run_for_document(document)&.status
        when "failed"
          "Needs review"
        when "previewed"
          "Import preview waiting confirmation"
        when "imported"
          "Imported"
        else
          "Uploaded - ready for CSV/XLSX import"
        end
      end

      def bas_document_content_type(document)
        return "" unless document.file.attached?

        document.file.blob.content_type.to_s
      end

      def tdk_workbook_sort_key(header)
        header.to_s == "source_row" ? "source_row" : header.to_s
      end
    end
  end
end
