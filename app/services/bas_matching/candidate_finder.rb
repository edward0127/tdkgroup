module BasMatching
  class CandidateFinder
    Candidate = Struct.new(:match_type, :invoices, :payment_record, :matched_amount, :rule, keyword_init: true)

    MAX_GROUP_SIZE = 5
    MIN_CONFIDENCE = 55

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
      bank_transactions.flat_map do |transaction|
        nearby_invoices = invoices_for_bank.select { |invoice| invoice.total_amount.present? && date_compatible?(invoice, transaction) }
        grouped_by_party(nearby_invoices).filter_map do |_party_key, invoices|
          next if invoices.size < 2 || invoices.size > MAX_GROUP_SIZE

          matching_group = matching_invoice_group(invoices, transaction)
          next if matching_group.blank?

          Candidate.new(
            match_type: "invoices_to_bank_transaction",
            invoices: matching_group,
            payment_record: transaction,
            matched_amount: transaction.amount.to_d.abs,
            rule: "grouped_invoices_to_bank"
          )
        end
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

    def grouped_by_party(invoices)
      invoices.group_by do |invoice|
        ConfidenceScorer.keyword_tokens(invoice.party_name).first || "unknown:#{invoice.id}"
      end
    end

    def matching_invoice_group(invoices, transaction)
      max_size = [ invoices.size, MAX_GROUP_SIZE ].min
      (2..max_size).each do |size|
        match = invoices.combination(size).find do |group|
          group.sum { |invoice| invoice.total_amount.to_d } == transaction.amount.to_d.abs
        end
        return match if match.present?
      end

      nil
    end

    def date_compatible?(invoice, transaction)
      dates = [ invoice.paid_date, invoice.issue_date ].compact
      return true if dates.blank? || transaction.transaction_date.blank?

      dates.any? { |date| (transaction.transaction_date - date).to_i.abs <= 21 }
    end
  end
end
