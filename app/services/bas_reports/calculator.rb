require "bigdecimal"
require "set"

module BasReports
  class Calculator
    Result = Data.define(:totals, :validation_errors)

    ZERO = BigDecimal("0").freeze
    GST_REVIEW_CODES = %w[unknown needs_review].freeze
    GST_INCLUDED_SALE_CODES = %w[taxable gst_free input_taxed no_gst].freeze

    def initialize(bas_job:)
      @bas_job = bas_job
      @validation_errors = []
      @summary = {
        g1_total_sales: ZERO,
        gst_on_sales_1a: ZERO,
        gst_on_purchases_1b: ZERO,
        net_gst_payable: ZERO
      }
      @payroll = {
        gross_wages: ZERO,
        payg_withheld: ZERO,
        super_amount: ZERO
      }
      @sales_detail = []
      @purchase_detail = []
      @cash_detail = []
      @ignored_items = []
    end

    def call
      add_job_configuration_errors
      calculate_invoices
      calculate_cash_transactions
      calculate_payroll
      apply_adjustments
      @summary[:net_gst_payable] = @summary[:gst_on_sales_1a] - @summary[:gst_on_purchases_1b]

      Result.new(totals: serialized_totals, validation_errors: validation_errors.uniq)
    end

    private

    attr_reader :bas_job, :validation_errors

    def add_job_configuration_errors
      validation_errors << "GST basis must be set before approval." if bas_job.gst_basis == "unknown"
      validation_errors << "Reporting method must be set before approval." if bas_job.reporting_method == "unknown"
      validation_errors << "Cancelled BAS jobs cannot be approved." if bas_job.status == "cancelled"
    end

    def calculate_invoices
      bas_job.invoices.find_each do |invoice|
        if invoice.status == "ignored" || invoice.gst_code == "bas_excluded"
          add_ignored_item(invoice)
          next
        end

        validate_invoice_for_calculation(invoice)
        next if invoice.status == "needs_review" || GST_REVIEW_CODES.include?(invoice.gst_code) || invoice.direction == "unknown"

        if bas_job.gst_basis == "cash"
          invoice_cash_basis_allocations(invoice).each do |allocation|
            apply_invoice_amount(invoice, allocation.fetch(:amount), allocation.fetch(:gst_amount), allocation.fetch(:date), "cash_basis_match")
          end
        elsif invoice.issue_date.present? && in_period?(invoice.issue_date)
          apply_invoice_amount(invoice, money(invoice.total_amount), money(invoice.gst_amount), invoice.issue_date, "accrual_issue_date")
        end
      end
    end

    def validate_invoice_for_calculation(invoice)
      validation_errors << "Invoice ##{invoice.id} is marked needs review." if invoice.status == "needs_review"
      validation_errors << "Invoice ##{invoice.id} has unknown GST treatment." if GST_REVIEW_CODES.include?(invoice.gst_code)
      validation_errors << "Invoice ##{invoice.id} has unknown direction." if invoice.direction == "unknown"

      if invoice.gst_code == "taxable" && invoice.gst_amount.blank?
        validation_errors << "Invoice ##{invoice.id} is taxable but has no GST amount."
      end

      if bas_job.gst_basis == "cash" && invoice.direction.in?(%w[sale purchase]) && invoice.total_amount.blank?
        validation_errors << "Invoice ##{invoice.id} needs a total amount for cash-basis allocation."
      end
    end

    def invoice_cash_basis_allocations(invoice)
      return [] if invoice.total_amount.blank?

      accepted_matches_for(invoice).each_with_object([]) do |match, allocations|
        payment_record = payment_record_for(match)
        next if payment_record.blank?

        payment_date = payment_date_for(payment_record)
        if payment_date.blank?
          validation_errors << "Accepted match ##{match.id} needs a payment date for cash-basis calculation."
          next
        end
        next unless in_period?(payment_date)

        allocated_amount = allocated_amount_for(match, invoice)
        gst_amount = proportional_gst(invoice, allocated_amount)
        allocations << { amount: allocated_amount, gst_amount: gst_amount, date: payment_date }
      end
    end

    def accepted_matches_for(invoice)
      invoice.matches.accepted.includes(items: :matchable)
    end

    def payment_record_for(match)
      match.items.map(&:matchable).find { |record| record.is_a?(BasBankTransaction) || record.is_a?(BasCashTransaction) }
    end

    def payment_date_for(payment_record)
      payment_record.respond_to?(:transaction_date) ? payment_record.transaction_date : nil
    end

    def allocated_amount_for(match, invoice)
      invoice_total = money(invoice.total_amount).abs
      invoice_item = match.items.detect { |item| item.matchable == invoice }
      item_amount = money(invoice_item&.amount || invoice.total_amount).abs

      if match.items.select { |item| item.matchable.is_a?(BasInvoice) }.one? && match.matched_amount.present?
        [ money(match.matched_amount).abs, invoice_total ].min
      else
        [ item_amount, invoice_total ].min
      end
    end

    def proportional_gst(invoice, allocated_amount)
      return ZERO if invoice.gst_amount.blank? || invoice.total_amount.blank?

      total = money(invoice.total_amount).abs
      return ZERO if total.zero?

      (money(invoice.gst_amount) * allocated_amount / total).round(2)
    end

    def apply_invoice_amount(invoice, total_amount, gst_amount, calculation_date, source)
      return if invoice.direction == "unknown"
      return if invoice.gst_code == "bas_excluded"

      signed_total = signed_amount_for_invoice(invoice, total_amount)
      signed_gst = signed_amount_for_invoice(invoice, gst_amount)

      if invoice.direction == "sale"
        @summary[:g1_total_sales] += signed_total if GST_INCLUDED_SALE_CODES.include?(invoice.gst_code)
        @summary[:gst_on_sales_1a] += signed_gst if invoice.gst_code == "taxable"
        @sales_detail << invoice_detail(invoice, signed_total, signed_gst, calculation_date, source)
      elsif invoice.direction == "purchase"
        @summary[:gst_on_purchases_1b] += signed_gst if invoice.gst_code == "taxable"
        @purchase_detail << invoice_detail(invoice, signed_total, signed_gst, calculation_date, source)
      end
    end

    def signed_amount_for_invoice(invoice, amount)
      value = money(amount)
      money(invoice.total_amount).negative? ? -value.abs : value
    end

    def invoice_detail(invoice, total_amount, gst_amount, calculation_date, source)
      {
        "source" => "BasInvoice",
        "source_id" => invoice.id,
        "date" => calculation_date&.to_fs(:db),
        "direction" => invoice.direction,
        "party" => invoice.party_name,
        "reference" => invoice.invoice_number,
        "description" => invoice.description,
        "gst_code" => invoice.gst_code,
        "total_amount" => serialize_money(total_amount),
        "gst_amount" => serialize_money(gst_amount),
        "calculation_source" => source
      }
    end

    def calculate_cash_transactions
      matched_cash_ids = cash_transaction_ids_matched_to_invoices

      bas_job.cash_transactions.find_each do |transaction|
        if transaction.status == "ignored" || transaction.gst_code == "bas_excluded"
          add_ignored_item(transaction)
          next
        end
        next if matched_cash_ids.include?(transaction.id)
        next if transaction.transaction_date.present? && !in_period?(transaction.transaction_date)

        validate_cash_transaction_for_calculation(transaction)
        next if transaction.status == "needs_review" || GST_REVIEW_CODES.include?(transaction.gst_code) || transaction.direction == "unknown"

        total_amount = money(transaction.total_amount)
        gst_amount = money(transaction.gst_amount)

        if transaction.direction == "cash_receipt"
          @summary[:g1_total_sales] += total_amount if GST_INCLUDED_SALE_CODES.include?(transaction.gst_code)
          @summary[:gst_on_sales_1a] += gst_amount if transaction.gst_code == "taxable"
        elsif transaction.direction == "cash_payment"
          @summary[:gst_on_purchases_1b] += gst_amount if transaction.gst_code == "taxable"
        end

        @cash_detail << cash_detail(transaction, total_amount, gst_amount)
      end
    end

    def cash_transaction_ids_matched_to_invoices
      BasMatchItem
        .joins(:bas_match)
        .where(bas_matches: { bas_job_id: bas_job.id, status: "accepted" }, matchable_type: "BasCashTransaction")
        .pluck(:matchable_id)
        .to_set
    end

    def validate_cash_transaction_for_calculation(transaction)
      validation_errors << "Cash transaction ##{transaction.id} is marked needs review." if transaction.status == "needs_review"
      validation_errors << "Cash transaction ##{transaction.id} has unknown GST treatment." if GST_REVIEW_CODES.include?(transaction.gst_code)
      validation_errors << "Cash transaction ##{transaction.id} has unknown direction." if transaction.direction == "unknown"

      if transaction.gst_code == "taxable" && transaction.gst_amount.blank?
        validation_errors << "Cash transaction ##{transaction.id} is taxable but has no GST amount."
      end
    end

    def cash_detail(transaction, total_amount, gst_amount)
      {
        "source" => "BasCashTransaction",
        "source_id" => transaction.id,
        "date" => transaction.transaction_date&.to_fs(:db),
        "direction" => transaction.direction,
        "party" => transaction.party_name,
        "description" => transaction.description,
        "gst_code" => transaction.gst_code,
        "total_amount" => serialize_money(total_amount),
        "gst_amount" => serialize_money(gst_amount)
      }
    end

    def calculate_payroll
      bas_job.payroll_summaries.find_each do |summary|
        @payroll[:gross_wages] += money(summary.gross_wages)
        @payroll[:payg_withheld] += money(summary.payg_withheld)
        @payroll[:super_amount] += money(summary.super_amount)
      end

      return unless bas_job.payroll_applicable?
      return if bas_job.payroll_summaries.exists? || bas_job.adjustments.where(adjustment_type: %w[payroll_gross_wages payg_withheld]).exists?

      validation_errors << "Payroll is marked applicable but no payroll summary or payroll adjustment exists."
    end

    def apply_adjustments
      bas_job.adjustments.find_each do |adjustment|
        next if adjustment.reason.blank?

        amount = money(adjustment.amount)
        case adjustment.adjustment_type
        when "gst_on_sales"
          @summary[:gst_on_sales_1a] += amount
        when "gst_on_purchases"
          @summary[:gst_on_purchases_1b] += amount
        when "total_sales"
          @summary[:g1_total_sales] += amount
        when "payroll_gross_wages"
          @payroll[:gross_wages] += amount
        when "payg_withheld"
          @payroll[:payg_withheld] += amount
        end
      end
    end

    def add_ignored_item(record)
      @ignored_items << {
        "source" => record.class.name,
        "source_id" => record.id,
        "status" => record.status,
        "gst_code" => record.respond_to?(:gst_code) ? record.gst_code : nil
      }
    end

    def serialized_totals
      {
        "job" => {
          "bas_job_id" => bas_job.id,
          "client_name" => bas_job.bas_client.display_name,
          "period_start" => bas_job.period_start&.to_fs(:db),
          "period_end" => bas_job.period_end&.to_fs(:db),
          "gst_basis" => bas_job.gst_basis,
          "reporting_method" => bas_job.reporting_method
        },
        "summary" => serialized_summary,
        "payroll" => @payroll.to_h { |key, amount| [ key.to_s, serialize_money(amount) ] },
        "adjustments" => serialized_adjustments,
        "gst_sales_detail" => @sales_detail,
        "gst_purchase_detail" => @purchase_detail,
        "cash_transaction_detail" => @cash_detail,
        "accepted_matches" => serialized_accepted_matches,
        "queries" => serialized_queries,
        "ignored_items" => @ignored_items,
        "generated_at" => Time.current.iso8601
      }
    end

    def serialized_summary
      exact = @summary.to_h { |key, amount| [ key.to_s, serialize_money(amount) ] }
      labels = @summary.transform_values { |amount| whole_dollar(amount) }

      exact.merge(
        "bas_labels" => {
          "G1" => labels.fetch(:g1_total_sales),
          "1A" => labels.fetch(:gst_on_sales_1a),
          "1B" => labels.fetch(:gst_on_purchases_1b),
          "net_gst_payable" => labels.fetch(:net_gst_payable)
        }
      )
    end

    def serialized_adjustments
      bas_job.adjustments.order(:created_at, :id).map do |adjustment|
        {
          "id" => adjustment.id,
          "adjustment_type" => adjustment.adjustment_type,
          "label" => adjustment.label,
          "amount" => serialize_money(adjustment.amount),
          "reason" => adjustment.reason,
          "created_by" => adjustment.created_by
        }
      end
    end

    def serialized_accepted_matches
      bas_job.matches.accepted.includes(items: :matchable).order(:created_at, :id).map do |match|
        {
          "id" => match.id,
          "match_type" => match.match_type,
          "matched_amount" => serialize_money(match.matched_amount),
          "accepted_by" => match.accepted_by,
          "accepted_at" => match.accepted_at&.iso8601,
          "items" => match.items.map do |item|
            {
              "source" => item.matchable_type,
              "source_id" => item.matchable_id,
              "amount" => serialize_money(item.amount)
            }
          end
        }
      end
    end

    def serialized_queries
      bas_job.queries.order(:status, :id).map do |query|
        {
          "id" => query.id,
          "query_type" => query.query_type,
          "status" => query.status,
          "title" => query.title,
          "auto_generated" => query.auto_generated,
          "source_type" => query.source_type,
          "source_id" => query.source_id
        }
      end
    end

    def in_period?(date)
      return false if date.blank? || bas_job.period_start.blank? || bas_job.period_end.blank?

      date >= bas_job.period_start && date <= bas_job.period_end
    end

    def money(value)
      return ZERO if value.blank?
      return value if value.is_a?(BigDecimal)

      BigDecimal(value.to_s)
    end

    def serialize_money(value)
      amount = money(value).round(2)
      sign = amount.negative? ? "-" : ""
      integer_part, decimal_part = amount.abs.to_s("F").split(".", 2)
      "#{sign}#{integer_part}.#{decimal_part.to_s.ljust(2, '0')[0, 2]}"
    end

    def whole_dollar(value)
      money(value).round(0, BigDecimal::ROUND_HALF_UP).to_i
    end
  end
end
