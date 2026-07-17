module BasTdk
  class DescriptionNormalizer
    GENERIC_BANK_TOKENS = %w[
      bank banking card debit credit eft eftpos pos visa mastercard payment payments
      purchase transaction transfer tfr deposit withdrawal withdraw direct online
      app mobile commbank cba anz nab westpac netbank osko payid bpay ref reference receipt
      effective date value pending processed australia aus au pty ltd limited
      account accounts to from via
    ].freeze

    GENERIC_ONLY_TOKENS = (GENERIC_BANK_TOKENS + %w[to from via at on the and]).freeze
    MIN_MATCHABLE_LENGTH = 4
    TEXTUAL_MONTH_PATTERN = "(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"
    MONTH_DAY_PATTERN = "(?:0?[1-9]|[12]\\d|3[01])"

    class << self
      def call(value)
        text = transliterated(value)
        text = remove_variable_noise(text)
        tokens = tokenize(text)
        tokens.reject! { |token| GENERIC_BANK_TOKENS.include?(token) }
        tokens.join(" ")
      end

      def tokens(value)
        call(value).split
      end

      def matchable?(value)
        normalized = call(value)
        return false if normalized.length < MIN_MATCHABLE_LENGTH

        meaningful = normalized.split.reject { |token| GENERIC_ONLY_TOKENS.include?(token) }
        meaningful.any? { |token| token.match?(/[a-z]/) }
      end

      def similarity(left, right)
        left_normalized = call(left)
        right_normalized = call(right)
        return 0.0 unless matchable?(left_normalized) && matchable?(right_normalized)
        return 1.0 if left_normalized == right_normalized

        left_tokens = left_normalized.split.uniq
        right_tokens = right_normalized.split.uniq
        token_union = left_tokens | right_tokens
        token_score = token_union.empty? ? 0.0 : (left_tokens & right_tokens).length.fdiv(token_union.length)

        [ token_score, trigram_dice(left_normalized, right_normalized) ].max
      end

      private

      def transliterated(value)
        text = value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: " ")
        ActiveSupport::Inflector.transliterate(text).downcase
      rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
        value.to_s.scrub(" ").downcase
      end

      def remove_variable_noise(text)
        cleaned = text
          .gsub(%r{\b\d{1,2}[/-]\d{1,2}[/-](?:\d{2}|\d{4})\b}, " ")
          .gsub(%r{\b\d{4}[/-]\d{1,2}[/-]\d{1,2}\b}, " ")
          .gsub(/\b#{MONTH_DAY_PATTERN}\s+#{TEXTUAL_MONTH_PATTERN}(?:\s+(?:19|20)\d{2})?\b/i, " ")
          .gsub(/\b#{TEXTUAL_MONTH_PATTERN}\s+#{MONTH_DAY_PATTERN}(?:,?\s+(?:19|20)\d{2})?\b/i, " ")
          .gsub(/\b\d{1,2}:\d{2}(?::\d{2})?\s*(?:am|pm)?\b/i, " ")
          .gsub(/\b(?:xx+|\*{2,})\s*\d{2,6}\b/i, " ")
          .gsub(/\b(?:ref(?:erence)?|receipt|trace|terminal|auth(?:orisation)?|serial|txn)\b\s*[:#-]?\s*[a-z0-9-]{4,}\b/i, " ")
          .gsub(/\bdoordashm[_-][a-z0-9]{6,}\b/i, "doordash")
          .gsub(/\b\d{6,}\b/, " ")

        remove_adyen_random_ids(cleaned)
      end

      def remove_adyen_random_ids(text)
        cleaned = text.dup
        nearby_id = /(\badyen\b.{0,120}?)\b(?:swpe|xch)[a-z0-9]{8,}\b/i
        cleaned.sub!(nearby_id, "\\1") while cleaned.match?(nearby_id)

        cleaned
      end

      def tokenize(text)
        text.scan(/[a-z]+(?:'[a-z]+)?|\d{1,5}/).reject { |token| token.match?(/\A0+\z/) }
      end

      def trigram_dice(left, right)
        left_grams = trigrams(left)
        right_grams = trigrams(right)
        return 0.0 if left_grams.empty? || right_grams.empty?

        overlap = left_grams.sum { |gram, count| [ count, right_grams.fetch(gram, 0) ].min }
        (2.0 * overlap) / (left_grams.values.sum + right_grams.values.sum)
      end

      def trigrams(value)
        compact = value.gsub(/\s+/, " ").strip
        return {} if compact.length < 3

        compact.chars.each_cons(3).map(&:join).tally
      end
    end
  end
end
