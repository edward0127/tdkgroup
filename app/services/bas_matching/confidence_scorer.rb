module BasMatching
  class ConfidenceScorer
    Result = Struct.new(:confidence, :explanation, keyword_init: true)

    DATE_WINDOW_DAYS = 21

    def self.score(invoice:, payment_record:)
      new.score(invoice: invoice, payment_record: payment_record)
    end

    def score(invoice:, payment_record:)
      score = 0
      reasons = []

      if amounts_equal?(invoice.total_amount, payment_amount(payment_record))
        score += 45
        reasons << "amount matches"
      end

      days = date_distance(invoice, payment_record)
      if days.present?
        if days <= 7
          score += 25
          reasons << "date is within #{days} days"
        elsif days <= DATE_WINDOW_DAYS
          score += 12
          reasons << "date is nearby"
        end
      end

      overlap = keyword_overlap(invoice.party_name, searchable_payment_text(payment_record))
      if overlap.positive?
        score += [ 20, overlap * 10 ].min
        reasons << "party keywords appear in payment text"
      end

      if payment_method_compatible?(invoice, payment_record)
        score += 10
        reasons << "payment method is compatible"
      end

      Result.new(confidence: [ score, 100 ].min, explanation: reasons.presence&.join(", ") || "amount/date candidate")
    end

    def self.amounts_equal?(left, right)
      new.amounts_equal?(left, right)
    end

    def amounts_equal?(left, right)
      return false if left.nil? || right.nil?

      left.to_d.abs == right.to_d.abs
    end

    def self.keyword_tokens(value)
      new.keyword_tokens(value)
    end

    def keyword_tokens(value)
      value.to_s
        .downcase
        .gsub(/[^a-z0-9]+/, " ")
        .split
        .reject { |token| token.length < 3 || token.in?(%w[the and pty ltd inc company synthetic]) }
        .uniq
    end

    private

    def payment_amount(payment_record)
      if payment_record.respond_to?(:amount)
        payment_record.amount
      else
        payment_record.total_amount
      end
    end

    def searchable_payment_text(payment_record)
      [
        payment_record.try(:description),
        payment_record.try(:details),
        payment_record.try(:reference),
        payment_record.try(:party_name)
      ].compact_blank.join(" ")
    end

    def keyword_overlap(party_name, payment_text)
      (keyword_tokens(party_name) & keyword_tokens(payment_text)).size
    end

    def date_distance(invoice, payment_record)
      invoice_dates = [ invoice.paid_date, invoice.issue_date ].compact
      payment_date = payment_record.try(:transaction_date)
      return nil if invoice_dates.blank? || payment_date.blank?

      invoice_dates.map { |date| (payment_date - date).to_i.abs }.min
    end

    def payment_method_compatible?(invoice, payment_record)
      case payment_record
      when BasBankTransaction
        invoice.payment_method.in?(%w[bank mixed unknown])
      when BasCashTransaction
        invoice.payment_method.in?(%w[cash mixed unknown])
      else
        false
      end
    end
  end
end
