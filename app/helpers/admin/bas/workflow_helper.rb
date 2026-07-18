require "digest"

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
      TDK_WORKBOOK_OPTIONAL_DETAIL_HEADER_PATTERN = /\b(details?|narration|reference|memo|notes?)\b/.freeze
      TDK_COLUMN_MAPPING_ROLE_OPTIONS = [
        [ "Ignore this column", "ignore" ],
        [ "Keep original column", "keep" ],
        [ "Date", "date" ],
        [ "Description", "description" ],
        [ "Amount", "amount" ],
        [ "Debit / withdrawal", "debit" ],
        [ "Credit / deposit", "credit" ],
        [ "Balance", "balance" ],
        [ "Details", "details" ],
        [ "Category", "category" ],
        [ "GST", "gst" ]
      ].freeze
      TDK_CODING_MAPPING_ROLE_OPTIONS = [
        [ "Ignore this column", "ignore" ],
        [ "Description", "description" ],
        [ "Category", "category" ],
        [ "Amount", "amount" ],
        [ "Debit / withdrawal", "debit" ],
        [ "Credit / deposit", "credit" ],
        [ "GST", "gst" ]
      ].freeze
      TDK_CODING_FILTER_OPTIONS = [
        [ "All", "all" ],
        [ "Needs review", "needs_review" ],
        [ "Prior-quarter matches", "prior_match" ],
        [ "Rules", "rules" ],
        [ "Manual", "manual" ],
        [ "Unclassified", "unclassified" ]
      ].freeze
      TDK_CODING_TABLE_COLUMNS = [
        { key: "date", label: "Date", class_name: "tdk-coding-col--date", default_width: 120, min_width: 105 },
        { key: "description", label: "Description", class_name: "tdk-coding-col--description", default_width: 240, min_width: 180 },
        { key: "amount", label: "Amount", class_name: "tdk-coding-col--amount", default_width: 120, min_width: 105 },
        { key: "category", label: "Category", class_name: "tdk-coding-col--category", default_width: 190, min_width: 150 },
        { key: "gst", label: "GST", class_name: "tdk-coding-col--gst", default_width: 130, min_width: 110 },
        { key: "source", label: "Source", class_name: "tdk-coding-col--source", default_width: 360, min_width: 240 },
        { key: "review", label: "Review", class_name: "tdk-coding-col--review", default_width: 120, min_width: 105 }
      ].map(&:freeze).freeze

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
        when "needs_mapping"
          "is-warning"
        when "queued", "processing"
          "is-working"
        when "superseded"
          "is-muted"
        else
          "is-neutral"
        end
      end

      def tdk_column_detection(workbook)
        detection = workbook&.metadata&.fetch("column_detection", nil)
        detection.is_a?(Hash) ? detection : {}
      end

      def tdk_column_detection_columns(workbook)
        Array(tdk_column_detection(workbook)["columns"]).select { |column| column.is_a?(Hash) }
      end

      def tdk_column_mapping_role_options
        TDK_COLUMN_MAPPING_ROLE_OPTIONS
      end

      def tdk_column_mapping_suggested_role(detection, column, workbook: nil)
        index = column["index"].to_s
        override = workbook&.metadata&.dig("column_mapping_override", "columns")
        confirmed = override[index] if override.is_a?(Hash)
        suggestions = detection["suggested_mapping"]
        suggested = suggestions[index] if suggestions.is_a?(Hash)
        suggested = column["suggested_role"] if suggested.blank?
        suggested = confirmed if confirmed.present?
        allowed = TDK_COLUMN_MAPPING_ROLE_OPTIONS.map(&:last)

        allowed.include?(suggested.to_s) ? suggested.to_s : "ignore"
      end

      def tdk_column_mapping_source_label(column)
        index = Integer(column["index"], exception: false)
        column_label = index.present? ? "Column #{tdk_spreadsheet_column_name(index)}" : "Source column"
        source_header = column["source_header"].presence
        fallback_label = column["label"].to_s
        source_header ||= fallback_label.presence unless fallback_label.match?(/\AColumn\s+[A-Z]+\b/i)

        source_header.present? ? "#{column_label} — #{source_header}" : column_label
      end

      def tdk_coding_detection(run)
        detection = run&.metadata&.fetch("column_detection", nil)
        detection.is_a?(Hash) ? detection : {}
      end

      def tdk_coding_detection_columns(run)
        Array(tdk_coding_detection(run)["columns"]).select { |column| column.is_a?(Hash) }
      end

      def tdk_coding_mapping_source_column(column)
        raw = column["source_column"] || column["index"]
        source_column = Integer(raw, exception: false)
        source_column = 1 if source_column == 0
        source_column
      end

      def tdk_coding_mapping_source_label(column)
        source_column = tdk_coding_mapping_source_column(column)
        column_label = source_column.present? ? "Column #{tdk_spreadsheet_column_name(source_column - 1)}" : "Source column"
        header = column["source_header"].presence || column["header"].presence || column["label"].presence
        header.present? ? "#{column_label} — #{header}" : column_label
      end

      def tdk_coding_mapping_samples(column)
        Array(column["samples"] || column["sample_values"]).compact_blank.first(5)
      end

      def tdk_coding_mapping_role_options
        TDK_CODING_MAPPING_ROLE_OPTIONS
      end

      def tdk_coding_mapping_suggested_role(run, column)
        index = tdk_coding_mapping_source_column(column).to_s
        confirmed_mapping = run&.column_mapping
        confirmed_role = if confirmed_mapping.is_a?(Hash)
          confirmed_mapping.find { |_role, source_index| source_index.to_s == index }&.first
        end
        suggestions = tdk_coding_detection(run)["suggested_mapping"]
        suggestion = suggestions[index] if suggestions.is_a?(Hash)
        suggestion ||= column["suggested_role"]
        candidate_roles = Array(column["candidate_roles"])
        suggestion ||= candidate_roles.first if candidate_roles.one?
        suggestion = confirmed_role if confirmed_role.present?
        allowed = TDK_CODING_MAPPING_ROLE_OPTIONS.map(&:last)

        allowed.include?(suggestion.to_s) ? suggestion.to_s : "ignore"
      end

      def tdk_coding_filter_options
        TDK_CODING_FILTER_OPTIONS
      end

      def tdk_coding_filter_link_params(filter)
        {
          tdk_step: "coding",
          coding_filter: filter == "all" ? nil : filter,
          coding_page: 1,
          coding_per_page: @tdk_coding_per_page,
          coding_sort: @tdk_coding_sort,
          coding_direction: @tdk_coding_direction,
          anchor: "tdk-coding-review"
        }.compact
      end

      def tdk_coding_page_link_params(page)
        {
          tdk_step: "coding",
          coding_filter: @tdk_coding_filter == "all" ? nil : @tdk_coding_filter,
          coding_page: page,
          coding_per_page: @tdk_coding_per_page,
          coding_sort: @tdk_coding_sort,
          coding_direction: @tdk_coding_direction,
          anchor: "tdk-coding-review"
        }.compact
      end

      def tdk_coding_table_columns
        TDK_CODING_TABLE_COLUMNS
      end

      def tdk_coding_column_width_storage_key(run)
        signature = Digest::SHA256.hexdigest(TDK_CODING_TABLE_COLUMNS.map { |column| column.fetch(:key) }.join("|")).first(16)
        "tdk-coding-column-widths:#{run&.id || "new"}:#{signature}"
      end

      def tdk_coding_sort_direction_for(column)
        key = column.fetch(:key)
        return "desc" if @tdk_coding_sort == key && @tdk_coding_direction == "asc"

        "asc"
      end

      def tdk_coding_sort_link_params(column)
        {
          tdk_step: "coding",
          coding_filter: @tdk_coding_filter == "all" ? nil : @tdk_coding_filter,
          coding_page: 1,
          coding_per_page: @tdk_coding_per_page,
          coding_sort: column.fetch(:key),
          coding_direction: tdk_coding_sort_direction_for(column),
          anchor: "tdk-coding-review"
        }.compact
      end

      def tdk_coding_sort_indicator(column)
        return "&#8597;".html_safe unless @tdk_coding_sort == column.fetch(:key)

        @tdk_coding_direction == "desc" ? "&darr;".html_safe : "&uarr;".html_safe
      end

      def tdk_coding_source_label(source, coding: nil, field: nil)
        return "Prior-quarter blank" if field.to_s == "gst" && tdk_coding_prior_quarter_blank?(coding)

        case source.to_s
        when "previous_quarter_exact"
          "Prior-quarter exact match"
        when "previous_quarter_fuzzy"
          case tdk_coding_match_type(coding)
          when "template"
            "Prior-quarter template match"
          when "merchant"
            "Prior-quarter merchant match"
          else
            "Prior-quarter similar match"
          end
        when "rule"
          "Rule suggestion"
        when "manual"
          "Manual"
        else
          "Unclassified"
        end
      end

      def tdk_coding_source_class(source, coding: nil, field: nil)
        return "is-neutral" if field.to_s == "gst" && tdk_coding_prior_quarter_blank?(coding)

        case source.to_s
        when "previous_quarter_exact", "previous_quarter_fuzzy"
          "is-history"
        when "rule"
          "is-rule"
        when "manual"
          "is-manual"
        else
          "is-unclassified"
        end
      end

      def tdk_coding_match_type(coding)
        coding&.metadata.to_h["match_type"].to_s
      end

      def tdk_coding_prior_quarter_blank?(coding)
        return false if coding.blank?
        return false unless coding.gst_source.to_s.start_with?("previous_quarter_")

        Array(coding.warning_codes).include?("historical_gst_blank_inherited")
      end

      def tdk_coding_warning_codes(coding)
        Array(coding.warning_codes).reject { |code| code == "historical_gst_blank_inherited" }
      end

      def tdk_coding_information_codes(coding)
        return [] unless tdk_coding_prior_quarter_blank?(coding)

        [ "Prior-quarter GST was blank" ]
      end

      def tdk_coding_reference_evidence_label(coding)
        match_type = tdk_coding_match_type(coding)
        return unless match_type.in?(%w[template merchant])

        row_number = coding.reference_source_row_number
        occurrences = coding.metadata.to_h["reference_occurrences"].to_i
        evidence_count = if occurrences.positive?
          "#{occurrences} #{match_type} #{"example".pluralize(occurrences)}"
        else
          "#{match_type} match"
        end
        return "Representative reference file row #{row_number} (#{evidence_count})" if row_number.present?

        "Reference file evidence (#{evidence_count})"
      end

      def tdk_coding_reference_example(coding)
        coding.reference_snapshot.to_h["description"].to_s.strip.presence
      end

      def tdk_coding_field_classes(coding, field)
        source = coding.public_send("#{field}_source")
        review_required = coding.public_send("#{field}_review_required")
        [
          "tdk-coding-field",
          "tdk-coding-field--#{source.to_s.tr("_", "-")}",
          ("tdk-coding-field--warning" if review_required)
        ].compact.join(" ")
      end

      def tdk_coding_category_value(coding)
        coding.suggested_category.presence || coding.workbook_row.row_data["Category"].to_s
      end

      def tdk_coding_gst_value(coding)
        value = coding.suggested_gst_amount
        value = coding.workbook_row.row_data["GST"] if value.nil?
        BasTdk::WorkbookValues.amount_input_value(value)
      end

      def tdk_coding_confidence_label(value)
        return if value.blank?

        "#{value.to_d.round}% confidence"
      end

      def tdk_coding_row_range_label
        return "Rows 0 of 0" if @tdk_coding_total_rows.to_i.zero?

        "Rows #{@tdk_coding_row_start}-#{@tdk_coding_row_end} of #{@tdk_coding_total_rows}"
      end

      def tdk_column_mapping_samples(column)
        Array(column["samples"]).compact_blank.first(5)
      end

      def tdk_spreadsheet_column_name(zero_based_index)
        number = zero_based_index.to_i + 1
        label = +""

        while number.positive?
          number, remainder = (number - 1).divmod(26)
          label.prepend((65 + remainder).chr)
        end

        label
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

      def tdk_workbook_table_headers(workbook, current_sort: nil, show_blank_optional: false)
        headers = Array(workbook&.processed_headers).compact
        filtered_headers = headers.reject do |header|
          tdk_workbook_blank_optional_header?(workbook, header) &&
            !show_blank_optional &&
            !tdk_workbook_same_header?(header, current_sort)
        end

        priority = [
          ->(header) { tdk_workbook_date_header?(header) },
          ->(header) { BasTdk::WorkbookValues.normalize_header(header).include?("category") },
          ->(header) { tdk_workbook_primary_amount_header?(header) },
          ->(header) { BasTdk::WorkbookValues.normalize_header(header) == "gst" },
          ->(header) { BasTdk::WorkbookValues.normalize_header(header).include?("description") },
          ->(header) { tdk_workbook_balance_header?(header) },
          ->(header) { tdk_workbook_optional_detail_header?(header) }
        ]

        remaining_headers = filtered_headers.each_with_index.to_a
        ordered_headers = []

        priority.each do |matcher|
          matching_headers, other_headers = remaining_headers.partition { |(header, _index)| matcher.call(header) }
          ordered_headers.concat(matching_headers.map(&:first))
          remaining_headers = other_headers
        end

        ordered_headers.concat(remaining_headers.map(&:first))
      end

      def tdk_workbook_optional_detail_header?(header)
        BasTdk::WorkbookValues.normalize_header(header).match?(TDK_WORKBOOK_OPTIONAL_DETAIL_HEADER_PATTERN)
      end

      def tdk_workbook_blank_optional_header?(workbook, header)
        return false if workbook.blank?
        return false unless tdk_workbook_optional_detail_header?(header)

        cache_key = [ workbook&.id, header.to_s ]
        @tdk_workbook_blank_optional_header_cache ||= {}
        return @tdk_workbook_blank_optional_header_cache[cache_key] if @tdk_workbook_blank_optional_header_cache.key?(cache_key)

        @tdk_workbook_blank_optional_header_cache[cache_key] = workbook.rows.all? do |row|
          row.row_data[header].to_s.strip.blank?
        end
      end

      def tdk_workbook_show_blank_optional_columns?
        params[:show_blank_optional_columns].to_s == "1"
      end

      def tdk_workbook_column_class(header)
        normalized = BasTdk::WorkbookValues.normalize_header(header)
        return "tdk-workbook-col--date" if normalized.include?("date")
        return "tdk-workbook-col--category" if normalized == "category" || normalized.include?("category")
        return "tdk-workbook-col--gst" if normalized == "gst" || normalized.include?("gst")
        return "tdk-workbook-col--balance" if tdk_workbook_balance_header?(header)
        return "tdk-workbook-col--amount" if normalized.match?(/\b(amount|debit|credit|net|gross|balance|paid)\b/)
        return "tdk-workbook-col--description" if normalized.include?("description")
        return "tdk-workbook-col--details" if tdk_workbook_optional_detail_header?(header)

        "tdk-workbook-col--medium"
      end

      def tdk_workbook_column_key(header)
        BasTdk::WorkbookValues.normalize_header(header).presence&.tr(" ", "_") || "column"
      end

      def tdk_workbook_column_default_width(header, compact_balance: false)
        normalized = BasTdk::WorkbookValues.normalize_header(header)
        return 144 if normalized.include?("date")
        return 190 if normalized == "category" || normalized.include?("category")
        return 96 if normalized == "gst" || normalized.include?("gst")
        return compact_balance ? 144 : 160 if tdk_workbook_balance_header?(header)
        return 128 if normalized.match?(/\b(amount|debit|credit|net|gross|paid)\b/)
        return 320 if normalized.include?("description")
        return 224 if tdk_workbook_optional_detail_header?(header)

        160
      end

      def tdk_workbook_column_min_width(header)
        normalized = BasTdk::WorkbookValues.normalize_header(header)
        return 144 if normalized.include?("date")
        return 144 if normalized == "category" || normalized.include?("category")
        return 96 if normalized == "gst" || normalized.include?("gst")
        return 128 if tdk_workbook_balance_header?(header)
        return 128 if normalized.match?(/\b(amount|debit|credit|net|gross|paid)\b/)
        return 160 if normalized.include?("description")
        return 128 if tdk_workbook_optional_detail_header?(header)

        128
      end

      def tdk_workbook_column_width_storage_key(workbook, headers)
        signature = Digest::SHA256.hexdigest(headers.map { |header| tdk_workbook_column_key(header) }.join("|")).first(16)
        "tdk-workbook-column-widths:#{workbook&.id || "new"}:#{signature}"
      end

      def tdk_workbook_column_width_style(header, rows)
        return unless tdk_workbook_balance_header?(header)

        max_length = rows.to_a.map { |row| tdk_workbook_amount_input_value(row.row_data[header]).to_s.length }.max.to_i
        ch = [ [ max_length + 3, 14 ].max, 22 ].min
        "--tdk-balance-input-width: #{ch}ch;"
      end

      def tdk_workbook_balance_header?(header)
        normalized = BasTdk::WorkbookValues.normalize_header(header)
        normalized == "balance" || normalized.include?("running balance")
      end

      def tdk_workbook_primary_amount_header?(header)
        normalized = BasTdk::WorkbookValues.normalize_header(header)
        BasTdk::WorkbookValues.amount_header?(header) && normalized != "gst" && !tdk_workbook_balance_header?(header)
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
          anchor: "tdk-active-table",
          show_blank_optional_columns: tdk_workbook_show_blank_optional_columns? ? "1" : nil
        }.compact
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
          anchor: "tdk-active-table",
          show_blank_optional_columns: tdk_workbook_show_blank_optional_columns? ? "1" : nil
        }.compact
      end

      def tdk_workbook_optional_columns_link_params(show_blank_optional:)
        {
          page: @tdk_page,
          per_page: @tdk_rows_per_page,
          sort: @tdk_sort,
          direction: @tdk_direction,
          anchor: "tdk-active-table",
          show_blank_optional_columns: show_blank_optional ? "1" : nil
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

      def tdk_workbook_same_header?(left, right)
        return false if left.blank? || right.blank?

        left.to_s == right.to_s || BasTdk::WorkbookValues.normalize_header(left) == BasTdk::WorkbookValues.normalize_header(right)
      end

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
