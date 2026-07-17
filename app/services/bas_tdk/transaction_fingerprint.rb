module BasTdk
  class TransactionFingerprint
    Result = Struct.new(:template_keys, :merchant_keys, keyword_init: true)

    TEMPLATE_PATTERNS = [
      [ "fast_transfer_from", /\Afast\s+transfer\s+from\b/ ],
      [ "fast_transfer_to", /\Afast\s+transfer\s+to\b/ ],
      [ "pos", /\Apos\b/ ],
      [ "weekly_pay", /\bweekly\s+pay\b/ ],
      [ "staff_wages", /\b(?:staff\s+wages?|wages?\s+batch)\b/ ]
    ].freeze

    MERCHANT_PATTERNS = [
      [ "bp", /\bbp\b/ ],
      [ "doordash", /\b(?:door\s+dash|doordash(?:mildura[a-z]*|m)?)\b/ ],
      [ "adyen", /\badyen\b/ ],
      [ "uber", /\buber(?:\s+bv)?\b/ ],
      [ "origin_energy", /\borigin\s+energy\b/ ],
      [ "eg_group", /\beg\s+group\b/ ],
      [ "officeworks", /\bofficeworks\b/ ],
      [ "adobe", /\badobe\b/ ],
      [ "telstra", /\btelstra\b/ ],
      [ "optus", /\boptus\b/ ],
      [ "agl", /\bagl\b/ ],
      [ "woolworths", /\bwoolworths\b/ ],
      [ "coles", /\bcoles\b/ ],
      [ "aldi", /\baldi\b/ ],
      [ "costco", /\bcostco\b/ ],
      [ "bunnings", /\bbunnings\b/ ],
      [ "kmart", /\bkmart\b/ ],
      [ "harvey_norman", /\bharvey\s+norman\b/ ],
      [ "cleanaway", /\bclean\s*away\b/ ],
      [ "mallee_meats", /\bmallee\s+meats?\b/ ],
      [ "uncle_monkeys", /\buncle\s+monkeys?\b/ ],
      [ "wagners_butcher", /\bwagners?\s+butcher(?:y)?\b/ ],
      [ "shop_rent", /\bshop\s+rent\b/ ],
      [ "australia_post", /\baustralia\s+post\b/ ],
      [ "xero", /\bxero\b/ ],
      [ "myob", /\bmyob\b/ ],
      [ "intuit", /\bintuit\b/ ]
    ].freeze

    class << self
      def call(description)
        new(description).call
      end
    end

    def initialize(description)
      @description = description
    end

    def call
      Result.new(
        template_keys: template_keys.freeze,
        merchant_keys: merchant_keys.freeze
      ).freeze
    end

    private

    def matching_keys(patterns)
      patterns.filter_map { |key, pattern| key if normalized_description.match?(pattern) }
    end

    def template_keys
      keys = matching_keys(TEMPLATE_PATTERNS)
      if normalized_description.match?(/\b(?:micro|test|verification)\s+deposits?\b/)
        keys.delete("fast_transfer_from")
        keys.delete("fast_transfer_to")
      end
      keys
    end

    def merchant_keys
      (matching_keys(MERCHANT_PATTERNS) + dynamic_merchant_keys).uniq.sort
    end

    def dynamic_merchant_keys
      keys = []
      if (match = normalized_description.match(/\bcommbank\s+app\s+(.+)\z/))
        memo = fingerprint_fragment(match[1])
        keys << "commbank_app_memo:#{memo}" if memo
        keys << "commbank_app_head:#{memo.split.first}" if memo
        keys << "commbank_app_tokens:#{memo.split.sort.join(' ')}" if memo&.split&.length.to_i.between?(2, 4)
      end
      if (match = normalized_description.match(/\A(?:fast\s+)?transfer\s+to\s+(.+?)\s+(?:commbank\s+app|netbank|cba\s+a\s+c|other\s+bank)\b/))
        party = fingerprint_fragment(match[1])
        keys << "transfer_party:#{party}" if party
      end
      if (match = normalized_description.match(/\bnetbank\s+(.+)\z/))
        raw_memo = match[1]
        unless raw_memo.match?(/\A(?:bpay|ref(?:erence)?|receipt|trace|terminal|auth|serial|txn|\d)\b/)
          memo = fingerprint_fragment(raw_memo)
          keys << "netbank_memo:#{memo}" if memo
          keys << "netbank_memo_head:#{memo.split.first(2).join(' ')}" if memo&.split&.length.to_i >= 2
        end
      end
      keys.compact
    end

    def fingerprint_fragment(value)
      normalized = BasTdk::DescriptionNormalizer.call(value)
      return if normalized.blank? || normalized.length < 3 || normalized.length > 80

      normalized
    end

    def normalized_description
      @normalized_description ||= begin
        text = @description.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: " ")
        ActiveSupport::Inflector.transliterate(text)
          .downcase
          .gsub(/[^a-z0-9]+/, " ")
          .squish
      rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
        @description.to_s.scrub(" ").downcase.gsub(/[^a-z0-9]+/, " ").squish
      end
    end
  end
end
