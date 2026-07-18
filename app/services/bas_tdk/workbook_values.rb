module BasTdk
  module WorkbookValues
    DATE_HEADERS = [
      "date",
      "transaction date",
      "txn date",
      "trans date",
      "value date",
      "posting date",
      "posted date"
    ].freeze

    AMOUNT_HEADER_PATTERN = /\b(amount|gst|net|gross|debits?|credits?|balance|paid|withdrawals?|deposits?|paid in|paid out)\b/.freeze
    NORMALIZED_AMOUNT_TEXT_PATTERN = /\A[+-]?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d+)?\z/.freeze
    AMOUNT_INPUT_PATTERN = "(?:[+-]?\\$?(?:\\d+|\\d{1,3}(?:,\\d{3})+)(?:\\.\\d+)?|\\(\\$?(?:\\d+|\\d{1,3}(?:,\\d{3})+)(?:\\.\\d+)?\\))".freeze
    AMOUNT_INPUT_TITLE = "Use a number such as 1000.00, 1,000.00, -1000.00, $1000.00, or ($1,000.00).".freeze
    EXCEL_DECIMAL_NOISE_TEXT_PATTERN = /\A[+-]?\d+\.\d+\z/.freeze
    EXCEL_DECIMAL_NOISE_MIN_FRACTION_LENGTH = 7
    EXCEL_DECIMAL_NOISE_TOLERANCE = BigDecimal("0.00000001")
    EXCEL_DATE_EPOCH = Date.new(1899, 12, 30)
    EXCEL_SERIAL_DATE_MIN = 20_000
    EXCEL_SERIAL_DATE_MAX = 100_000
    MONTH_NAME_DATE_PATTERNS = [
      /\A(?<day>\d{1,2})\s+(?<month>[[:alpha:]]+)\s+(?<year>\d{2}|\d{4})\z/,
      /\A(?<day>\d{1,2})-(?<month>[[:alpha:]]+)-(?<year>\d{2}|\d{4})\z/
    ].freeze
    ENGLISH_MONTH_NUMBERS = begin
      month_numbers = {}
      Date::MONTHNAMES.each_with_index do |name, index|
        month_numbers[name.downcase] = index if name.present?
      end
      Date::ABBR_MONTHNAMES.each_with_index do |name, index|
        month_numbers[name.downcase] = index if name.present?
      end
      month_numbers["sept"] = 9
      month_numbers
    end.freeze

    module_function

    def normalize_header(header)
      header.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
    end

    def date_header?(header)
      DATE_HEADERS.include?(normalize_header(header))
    end

    def amount_header?(header)
      normalize_header(header).match?(AMOUNT_HEADER_PATTERN)
    end

    def parse_date(value)
      return value if value.is_a?(Date)
      return value.to_date if value.respond_to?(:to_date) && (value.is_a?(Time) || value.is_a?(DateTime))

      text = value.to_s.strip
      return if text.blank?

      if (match = text.match(/\A(\d{4}-\d{1,2}-\d{1,2})(?:[ T]\d{1,2}:\d{2}(?::\d{2})?(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)?\z/))
        return Date.strptime(match[1], "%Y-%m-%d")
      end

      if (match = text.match(/\A(?<day>\d{1,2})\/(?<month>\d{1,2})\/(?<year>\d{2}|\d{4})(?:\s+\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?)?\z/i))
        return Date.new(normalized_bank_statement_year(match[:year]), match[:month].to_i, match[:day].to_i)
      end

      if (match = text.match(/\A(?<year>\d{4})\/(?<month>\d{1,2})\/(?<day>\d{1,2})(?:\s+\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?)?\z/i))
        return Date.new(match[:year].to_i, match[:month].to_i, match[:day].to_i)
      end

      if (date = parse_month_name_date(text))
        return date
      end

      if numeric_text?(text)
        serial = BigDecimal(text).to_i
        EXCEL_DATE_EPOCH + serial if serial >= EXCEL_SERIAL_DATE_MIN && serial < EXCEL_SERIAL_DATE_MAX
      end
    rescue ArgumentError
      nil
    end

    def iso_date_value(value)
      parse_date(value)&.iso8601.to_s
    end

    def parse_amount(value)
      return BigDecimal(value.to_s) if value.is_a?(Numeric)

      text = value.to_s.strip
      return if text.blank?

      return unless amount_text_format?(text)

      accounting_sign = amount_accounting_sign(text)
      negative_parentheses = text.match?(/\A\(.+\)\z/)
      normalized = normalize_amount_text(text).delete(",")

      decimal = BigDecimal(normalized)
      return -decimal.abs if accounting_sign == :debit || negative_parentheses
      return decimal.abs if accounting_sign == :credit

      decimal
    rescue ArgumentError
      nil
    end

    def valid_amount_input?(value)
      return true if value.is_a?(Numeric)

      text = value.to_s.strip
      text.blank? || amount_text_format?(text)
    end

    def amount_input_value(value)
      decimal = parse_amount(value)
      return value.to_s if decimal.nil?

      format_amount(decimal)
    end

    def rounded_amount(value)
      decimal = parse_amount(value)
      decimal&.round(2)
    end

    def clean_excel_decimal_noise(value)
      text = value.to_s
      stripped = text.strip
      return text unless excel_decimal_noise?(stripped)

      fixed_decimal(BigDecimal(stripped).round(2), 2)
    rescue ArgumentError
      text
    end

    def excel_decimal_noise?(value)
      text = value.to_s.strip
      return false unless text.match?(EXCEL_DECIMAL_NOISE_TEXT_PATTERN)

      fraction = text.split(".", 2).last.to_s
      return false if fraction.length < EXCEL_DECIMAL_NOISE_MIN_FRACTION_LENGTH

      decimal = BigDecimal(text)
      rounded = decimal.round(2)
      (decimal - rounded).abs < EXCEL_DECIMAL_NOISE_TOLERANCE
    rescue ArgumentError
      false
    end

    def format_amount(decimal)
      rounded = decimal.round(2)
      formatted = grouped_decimal(rounded.abs)
      rounded.negative? ? "(#{formatted})" : formatted
    end

    def numeric_text?(text)
      text.to_s.match?(/\A-?\d+(?:\.\d+)?\z/)
    end

    def parse_month_name_date(text)
      match = MONTH_NAME_DATE_PATTERNS.lazy.filter_map { |pattern| text.match(pattern) }.first
      return if match.blank?

      month = ENGLISH_MONTH_NUMBERS[match[:month].downcase]
      return if month.blank?

      Date.new(normalized_bank_statement_year(match[:year]), month, match[:day].to_i)
    end

    def normalized_bank_statement_year(year)
      text = year.to_s
      return 2000 + text.to_i if text.length == 2

      text.to_i
    end

    def grouped_decimal(decimal)
      whole, fraction = decimal.to_s("F").split(".", 2)
      grouped = whole.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      "#{grouped}.#{fraction.to_s.ljust(2, "0").first(2)}"
    end

    def fixed_decimal(decimal, places)
      whole, fraction = decimal.to_s("F").split(".", 2)
      "#{whole}.#{fraction.to_s.ljust(places, "0").first(places)}"
    end

    def amount_text_format?(text)
      normalize_amount_text(text).match?(NORMALIZED_AMOUNT_TEXT_PATTERN)
    end

    def normalize_amount_text(text)
      normalized = text.to_s.strip
      normalized = normalized.sub(/\s*(?:CR|DR)\z/i, "").strip
      normalized = normalized.delete_suffix("-").strip if normalized.end_with?("-")
      normalized = normalized.delete_prefix("(").delete_suffix(")").strip if normalized.match?(/\A\(.+\)\z/)
      normalized = normalized.delete_prefix("+").strip if normalized.start_with?("+$")
      normalized = normalized.sub(/\A([-+])\$/, "\\1")
      normalized = normalized.sub(/\A\$([-+])/, "\\1")
      normalized.delete_prefix("$").strip
    end

    def amount_accounting_sign(text)
      stripped = text.to_s.strip
      return :debit if stripped.match?(/DR\z/i) || stripped.end_with?("-")
      return :credit if stripped.match?(/CR\z/i)

      nil
    end
  end
end
