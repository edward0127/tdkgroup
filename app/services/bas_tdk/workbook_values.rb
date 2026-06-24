module BasTdk
  module WorkbookValues
    DATE_HEADERS = [
      "date",
      "transaction date",
      "txn date",
      "trans date",
      "value date"
    ].freeze

    AMOUNT_HEADER_PATTERN = /\b(amount|gst|net|gross|debit|credit|balance|paid|withdrawal|deposit|paid in|paid out)\b/.freeze
    AMOUNT_TEXT_PATTERN = /\A[+-]?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d+)?\z/.freeze
    NEGATIVE_PARENTHESES_AMOUNT_TEXT_PATTERN = /\A\((?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d+)?\)\z/.freeze
    AMOUNT_INPUT_PATTERN = "(?:[+-]?(?:\\d+|\\d{1,3}(?:,\\d{3})+)(?:\\.\\d+)?|\\((?:\\d+|\\d{1,3}(?:,\\d{3})+)(?:\\.\\d+)?\\))".freeze
    AMOUNT_INPUT_TITLE = "Use a number such as 1000.00, 1,000.00, -1000.00, or (1,000.00).".freeze
    EXCEL_DECIMAL_NOISE_TEXT_PATTERN = /\A[+-]?\d+\.\d+\z/.freeze
    EXCEL_DECIMAL_NOISE_MIN_FRACTION_LENGTH = 7
    EXCEL_DECIMAL_NOISE_TOLERANCE = BigDecimal("0.00000001")
    EXCEL_DATE_EPOCH = Date.new(1899, 12, 30)

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

      if text.match?(/\A\d{4}-\d{1,2}-\d{1,2}\z/)
        return Date.strptime(text, "%Y-%m-%d")
      end

      if text.match?(/\A\d{1,2}\/\d{1,2}\/\d{4}\z/)
        return Date.strptime(text, "%d/%m/%Y")
      end

      if numeric_text?(text)
        serial = BigDecimal(text).to_i
        return EXCEL_DATE_EPOCH + serial if serial.positive? && serial < 100_000
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

      negative_parentheses = text.match?(/\A\(.+\)\z/)
      normalized = text.delete(",").delete_prefix("(").delete_suffix(")").strip

      decimal = BigDecimal(normalized)
      negative_parentheses ? -decimal.abs : decimal
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
      text.match?(AMOUNT_TEXT_PATTERN) || text.match?(NEGATIVE_PARENTHESES_AMOUNT_TEXT_PATTERN)
    end
  end
end
