module BasMatching
  class CandidateFinder
    Candidate = Struct.new(
      :match_type,
      :invoices,
      :payment_record,
      :matched_amount,
      :rule,
      :confidence,
      :explanation,
      keyword_init: true
    )

    MAX_GROUP_SIZE = 3
    GROUP_CANDIDATE_POOL_LIMIT = 18
    GROUP_REVIEW_WINDOW_DAYS = 21
    GROUP_MIN_CONFIDENCE = 80
    MIN_CONFIDENCE = 55
    GROUPED_EXPLANATION = "Multiple invoices total the same amount as this bank transaction within the review window. Please review before accepting.".freeze

    def initialize(bas_job:)
      @bas_job = bas_job
      @scorer = ConfidenceScorer.new
    end

    def candidates
      exact_invoice_to_bank_candidates +
        grouped_invoice_to_bank_candidates +
        invoice_to_cash_candidates
    end

    private

    attr_reader :bas_job, :scorer

    def exact_invoice_to_bank_candidates
      invoices_for_bank.flat_map do |invoice|
        bank_transactions.select { |transaction| scorer.amounts_equal?(invoice.total_amount, transaction.amount) }
          .filter_map do |transaction|
            scored = scorer.score(invoice: invoice, payment_record: transaction)
            next if scored.confidence < MIN_CONFIDENCE

            Candidate.new(
              match_type: "invoice_to_bank_transaction",
              invoices: [ invoice ],
              payment_record: transaction,
              matched_amount: invoice.total_amount,
              rule: "exact_invoice_to_bank"
            )
          end
      end
    end

    def grouped_invoice_to_bank_candidates
      bank_transactions.filter_map do |transaction|
        invoice_pool = grouped_invoice_pool(transaction)
        next if invoice_pool.size < 2

        matching_groups = matching_invoice_groups(invoice_pool, transaction)
        next unless matching_groups.one?

        matching_group = matching_groups.first
        scored = score_grouped_candidate(matching_group, transaction, matching_groups.size)
        next if scored.confidence < GROUP_MIN_CONFIDENCE

        Candidate.new(
          match_type: "invoices_to_bank_transaction",
          invoices: matching_group,
          payment_record: transaction,
          matched_amount: money(transaction.amount).abs,
          rule: "grouped_invoices_to_bank",
          confidence: scored.confidence,
          explanation: scored.explanation
        )
      end
    end

    def invoice_to_cash_candidates
      invoices_for_cash.flat_map do |invoice|
        cash_transactions.select { |transaction| scorer.amounts_equal?(invoice.total_amount, transaction.total_amount) }
          .filter_map do |transaction|
            scored = scorer.score(invoice: invoice, payment_record: transaction)
            next if scored.confidence < MIN_CONFIDENCE

            Candidate.new(
              match_type: "invoice_to_cash_transaction",
              invoices: [ invoice ],
              payment_record: transaction,
              matched_amount: invoice.total_amount,
              rule: "invoice_to_cash"
            )
          end
      end
    end

    def invoices_for_bank
      @invoices_for_bank ||= bas_job.invoices.matchable
        .where(payment_method: %w[bank mixed unknown])
        .where.not(total_amount: nil)
        .to_a
        .reject { |invoice| locked_by_existing_decision?(invoice) }
    end

    def invoices_for_cash
      @invoices_for_cash ||= bas_job.invoices.matchable
        .where(payment_method: %w[cash mixed unknown])
        .where.not(total_amount: nil)
        .to_a
        .reject { |invoice| locked_by_existing_decision?(invoice) }
    end

    def bank_transactions
      @bank_transactions ||= bas_job.bank_transactions.matchable
        .where.not(amount: nil)
        .to_a
        .reject { |transaction| locked_by_existing_decision?(transaction) }
    end

    def cash_transactions
      @cash_transactions ||= bas_job.cash_transactions.matchable
        .where.not(total_amount: nil)
        .to_a
        .reject { |transaction| locked_by_existing_decision?(transaction) }
    end

    def locked_by_existing_decision?(record)
      record.matches.where(status: %w[accepted rejected needs_review]).exists?
    end

    def grouped_invoice_pool(transaction)
      invoices_for_bank
        .select { |invoice| grouped_invoice_candidate?(invoice, transaction) }
        .sort_by { |invoice| grouped_invoice_sort_key(invoice, transaction) }
        .first(GROUP_CANDIDATE_POOL_LIMIT)
    end

    def grouped_invoice_candidate?(invoice, transaction)
      invoice.total_amount.present? &&
        invoice.gst_code != "bas_excluded" &&
        direction_compatible?(invoice, transaction) &&
        grouped_date_compatible?(invoice, transaction) &&
        grouped_keyword_evidence?(invoice, transaction)
    end

    def matching_invoice_groups(invoices, transaction)
      target_amount = money(transaction.amount).abs
      groups = []
      max_size = [ invoices.size, MAX_GROUP_SIZE ].min

      (2..max_size).each do |size|
        invoices.combination(size).each do |group|
          next unless money_sum(group) == target_amount

          groups << group
          return groups if groups.size > 1
        end
      end

      groups
    end

    def score_grouped_candidate(group, transaction, matching_group_count)
      score = 50
      reasons = [ "exact invoice total matches bank transaction amount" ]

      if grouped_paid_date_evidence?(group, transaction)
        score += 15
        reasons << "invoice paid dates are near the bank transaction date"
      elsif group.all? { |invoice| grouped_date_distance(invoice, transaction).to_i <= 7 }
        score += 12
        reasons << "invoice dates are near the bank transaction date"
      else
        score += 6
        reasons << "invoice dates are within the review window"
      end

      if group.all? { |invoice| grouped_keyword_overlap(invoice, transaction).positive? }
        score += 15
        reasons << "bank text references each invoice"
      elsif group.any? { |invoice| grouped_keyword_overlap(invoice, transaction).positive? }
        score += 6
        reasons << "bank text references part of the group"
      end

      if matching_group_count == 1
        score += 10
        reasons << "candidate group is unique"
      end

      ConfidenceScorer::Result.new(
        confidence: [ score, 100 ].min,
        explanation: "#{GROUPED_EXPLANATION} Evidence: #{reasons.join(', ')}."
      )
    end

    def date_compatible?(invoice, transaction)
      dates = [ invoice.paid_date, invoice.issue_date ].compact
      return true if dates.blank? || transaction.transaction_date.blank?

      dates.any? { |date| (transaction.transaction_date - date).to_i.abs <= 21 }
    end

    def grouped_date_compatible?(invoice, transaction)
      grouped_date_distance(invoice, transaction).present?
    end

    def grouped_date_distance(invoice, transaction)
      return if transaction.transaction_date.blank?

      dates = [ invoice.paid_date, invoice.issue_date ].compact
      distances = dates.map { |date| (transaction.transaction_date - date).to_i.abs }
      distances.select { |distance| distance <= GROUP_REVIEW_WINDOW_DAYS }.min
    end

    def grouped_paid_date_evidence?(group, transaction)
      return false if transaction.transaction_date.blank?

      group.all? do |invoice|
        invoice.paid_date.present? &&
          (transaction.transaction_date - invoice.paid_date).to_i.abs <= GROUP_REVIEW_WINDOW_DAYS
      end
    end

    def direction_compatible?(invoice, transaction)
      amount = money(transaction.amount)
      return false if amount.zero?

      if amount.negative?
        invoice.direction.in?(%w[purchase unknown])
      else
        invoice.direction.in?(%w[sale unknown])
      end
    end

    def grouped_keyword_evidence?(invoice, transaction)
      payment_tokens = keyword_tokens(searchable_bank_text(transaction))
      invoice_tokens = keyword_tokens(searchable_invoice_text(invoice))
      return false if payment_tokens.blank?
      return true if invoice_tokens.blank?

      (invoice_tokens & payment_tokens).any?
    end

    def grouped_keyword_overlap(invoice, transaction)
      (keyword_tokens(searchable_invoice_text(invoice)) & keyword_tokens(searchable_bank_text(transaction))).size
    end

    def grouped_invoice_sort_key(invoice, transaction)
      [
        grouped_date_distance(invoice, transaction) || GROUP_REVIEW_WINDOW_DAYS + 1,
        -grouped_keyword_overlap(invoice, transaction),
        invoice.id
      ]
    end

    def searchable_invoice_text(invoice)
      [
        invoice.party_name,
        invoice.description,
        invoice.invoice_number,
        invoice.notes
      ].compact_blank.join(" ")
    end

    def searchable_bank_text(transaction)
      [
        transaction.description,
        transaction.details,
        transaction.reference,
        transaction.notes,
        transaction.bank_account_name
      ].compact_blank.join(" ")
    end

    def keyword_tokens(value)
      scorer.keyword_tokens(value)
    end

    def money(value)
      value.to_d.round(2)
    end

    def money_sum(invoices)
      invoices.sum(BigDecimal("0")) { |invoice| money(invoice.total_amount) }.abs
    end
  end
end
