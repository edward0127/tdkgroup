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
            action_label: locked ? nil : "Upload source/supporting file",
            action_path: locked ? nil : new_admin_bas_job_document_path(job)
          },
          {
            title: "Step 2: Import / convert",
            description: "Import CSV/XLSX files into BAS records, or convert standard bank PDF statements to a reviewable import preview.",
            status: bas_workflow_status(locked: locked, completed: imported_records_count.positive?, action_required: documents_count.positive? && imported_records_count.zero?),
            action_label: locked ? nil : "CSV/XLSX imports",
            action_path: locked ? nil : admin_bas_job_import_runs_path(job)
          },
          {
            title: "Step 3: Match records",
            description: "Create match suggestions and review them before generating client queries.",
            status: bas_workflow_status(locked: locked, completed: imported_records_count.positive? && matching_review_count.zero?, action_required: matching_review_count.positive? || imported_records_count.positive?),
            action_label: locked ? nil : "Matching & review",
            action_path: locked ? nil : admin_bas_job_matching_path(job)
          },
          {
            title: "Step 4: Generate client queries",
            description: "Create query list and email draft after match review is complete.",
            status: bas_workflow_status(locked: locked, completed: open_queries_count.positive?, action_required: imported_records_count.positive? && matching_review_count.zero? && open_queries_count.zero?),
            action_label: locked ? nil : "Open matching review",
            action_path: locked ? nil : admin_bas_job_matching_path(job)
          },
          {
            title: "Step 5: Review BAS report",
            description: "Calculate draft BAS figures and review approval blockers.",
            status: bas_workflow_status(locked: locked, completed: latest_report_snapshot.present? && approval_blockers_count.zero?, action_required: approval_blockers_count.positive? || (imported_records_count.positive? && latest_report_snapshot.blank?)),
            action_label: locked ? nil : "Report & snapshots",
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
            action_label: latest_report_snapshot.present? ? "Open latest snapshot" : "Report & snapshots",
            action_path: latest_report_snapshot.present? ? admin_bas_job_report_snapshot_path(job, latest_report_snapshot) : admin_bas_job_report_path(job)
          }
        ]
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

      def bas_document_status_label(document)
        return "Stored only - no import needed" if bas_supporting_only_document?(document)
        return bas_pdf_bank_statement_status_label(document) if bas_pdf_bank_statement_document?(document)
        return bas_spreadsheet_status_label(document) if bas_spreadsheet_importable_document?(document)
        return "Needs review" if document.processing_status.in?(%w[failed needs_review])

        "Stored only - no import needed"
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
    end
  end
end
