module BasMatching
  class QueryGenerator
    class LockedJobError < StandardError; end

    def initialize(bas_job:, actor_username:)
      @bas_job = bas_job
      @actor_username = actor_username
      @created_count = 0
      @existing_count = 0
    end

    attr_reader :created_count, :existing_count

    def call
      raise LockedJobError, "locked BAS jobs cannot generate queries" if bas_job.locked?

      generate_unmatched_bank_queries
      generate_unmatched_invoice_queries
      generate_invoice_gst_queries
      generate_cash_review_queries
      generate_direction_review_queries
      generate_payroll_queries
      generate_import_error_queries

      bas_job.update!(status: bas_job.queries.open_items.exists? ? "queries_open" : "review_ready")
      create_audit_event
      created_count
    end

    private

    attr_reader :bas_job, :actor_username

    def generate_unmatched_bank_queries
      bas_job.bank_transactions.unmatched.find_each do |transaction|
        create_query!(
          source: transaction,
          query_type: "unmatched_bank_transaction",
          title: "Unmatched bank transaction",
          details: "Bank transaction needs supporting invoice, receipt or review.",
          rule: "unmatched_bank_transaction"
        )
      end
    end

    def generate_unmatched_invoice_queries
      bas_job.invoices.unmatched.find_each do |invoice|
        create_query!(
          source: invoice,
          query_type: "unmatched_invoice",
          title: "Unmatched invoice",
          details: "Invoice has not been matched to a bank or cash transaction.",
          rule: "unmatched_invoice"
        )
      end
    end

    def generate_invoice_gst_queries
      bas_job.invoices.where.not(status: "ignored").where(gst_code: %w[unknown needs_review]).find_each do |invoice|
        create_query!(
          source: invoice,
          query_type: "unreviewed_gst_code",
          title: "GST code needs review",
          details: "Invoice GST code is unknown or needs review.",
          rule: "invoice_gst_code_review"
        )
      end

      bas_job.invoices.where.not(status: "ignored").where(gst_amount: nil).find_each do |invoice|
        create_query!(
          source: invoice,
          query_type: "gst_treatment_unclear",
          title: "GST amount missing",
          details: "Invoice GST amount is missing and GST treatment needs review.",
          rule: "invoice_missing_gst_amount"
        )
      end
    end

    def generate_cash_review_queries
      bas_job.cash_transactions.where(status: "needs_review").find_each do |transaction|
        create_query!(
          source: transaction,
          query_type: "cash_transaction_unclear",
          title: "Cash transaction needs review",
          details: "Cash transaction has been marked for admin review.",
          rule: "cash_transaction_needs_review"
        )
      end
    end

    def generate_direction_review_queries
      active_invoices.where(direction: "unknown").find_each do |invoice|
        create_query!(
          source: invoice,
          query_type: "invoice_direction_unclear",
          title: "Invoice direction unclear",
          details: "Invoice direction is unknown. Confirm whether this is a sale or purchase.",
          rule: "invoice_direction_unclear"
        )
      end

      active_cash_transactions.where(direction: "unknown").find_each do |transaction|
        create_query!(
          source: transaction,
          query_type: "cash_transaction_direction_unclear",
          title: "Cash transaction direction unclear",
          details: "Cash transaction direction is unknown. Confirm whether this is a receipt or payment.",
          rule: "cash_transaction_direction_unclear"
        )
      end
    end

    def generate_payroll_queries
      return unless bas_job.payroll_applicable?
      return if bas_job.payroll_summaries.exists?

      create_query!(
        source: bas_job,
        query_type: "payroll_unclear",
        title: "Payroll summary missing",
        details: "Payroll is marked applicable but no payroll summary has been imported.",
        rule: "payroll_summary_missing"
      )
    end

    def generate_import_error_queries
      bas_job.import_runs.where.not(error_count: 0).find_each do |import_run|
        next if import_run.import_errors.blank?

        create_query!(
          source: import_run,
          query_type: "import_error",
          title: "Import row errors need review",
          details: "Import run has row errors that need admin review.",
          rule: "import_run_row_errors"
        )
      end
    end

    def create_query!(source:, query_type:, title:, details:, rule:)
      dedupe_key = "#{rule}:#{source.class.name}:#{source.id}"
      existing = bas_job.queries.find_by(dedupe_key: dedupe_key)
      if existing.present?
        @existing_count += 1
        return
      end

      bas_job.queries.create!(
        query_type: query_type,
        status: "open",
        title: generated_title(fallback_title: title, source: source),
        details: details,
        created_by: actor_username,
        updated_by: actor_username,
        source_type: source.class.name,
        source_id: source.id,
        dedupe_key: dedupe_key,
        generated_by_rule: rule,
        auto_generated: true
      )
      @created_count += 1
    end

    def generated_title(fallback_title:, source:)
      parts = [
        fallback_title,
        source_party_description(source),
        formatted_money(source_amount(source))
      ].compact_blank

      return fallback_title if parts.size <= 1

      parts.join("  ")
    end

    def source_party_description(source)
      case source
      when BasBankTransaction
        first_present(source.description, source.details, source.reference)
      when BasInvoice
        first_present(source.party_name, source.description, source.invoice_number)
      when BasCashTransaction
        first_present(source.party_name, source.description)
      when BasPayrollSummary
        "Payroll summary ##{source.id}"
      when BasImportRun
        first_present(source.bas_document&.title, "Import run ##{source.id}")
      when BasJob
        source.period_label
      end
    end

    def source_amount(source)
      case source
      when BasBankTransaction
        source.amount
      when BasInvoice, BasCashTransaction
        source.total_amount
      when BasPayrollSummary
        source.gross_wages
      end
    end

    def first_present(*values)
      values.map { |value| value.to_s.squish }.find(&:present?)
    end

    def formatted_money(value)
      return nil if value.blank?

      amount = BigDecimal(value.to_s).round(2)
      sign = amount.negative? ? "-" : ""
      integer_part, decimal_part = amount.abs.to_s("F").split(".", 2)
      "#{sign}$#{integer_part}.#{decimal_part.to_s.ljust(2, '0')[0, 2]}"
    end

    def active_invoices
      bas_job.invoices.where.not(status: "ignored").where.not(gst_code: "bas_excluded")
    end

    def active_cash_transactions
      bas_job.cash_transactions.where.not(status: "ignored").where.not(gst_code: "bas_excluded")
    end

    def create_audit_event
      BasAuditEvent.create!(
        bas_job: bas_job,
        event_type: "bas_queries_generated",
        actor_username: actor_username,
        metadata: {
          created_count: created_count,
          existing_count: existing_count,
          open_query_count: bas_job.queries.open_items.count,
          status: bas_job.status
        }
      )
    end
  end
end
