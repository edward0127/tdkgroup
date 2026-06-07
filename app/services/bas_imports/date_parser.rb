require "date"
require "bigdecimal"

module BasImports
  class DateParser
    class ParseError < StandardError; end

    EXCEL_EPOCH = Date.new(1899, 12, 30)

    def self.parse(value)
      new.parse(value)
    end

    def self.parse!(value)
      new.parse!(value)
    end

    def parse(value)
      parse!(value)
    rescue ParseError
      nil
    end

    def parse!(value)
      return nil if value.nil?
      return value if value.is_a?(Date)
      return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String) && !value.is_a?(Numeric)

      return excel_serial_date(value) if value.is_a?(Numeric)

      string = value.to_s.strip
      return nil if string.blank?

      return Date.strptime(string, "%d/%m/%Y") if string.match?(/\A\d{1,2}\/\d{1,2}\/\d{4}\z/)
      return Date.strptime(string, "%Y-%m-%d") if string.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      return Date.strptime(string, "%d-%m-%Y") if string.match?(/\A\d{1,2}-\d{1,2}-\d{4}\z/)

      raise ParseError, "invalid date"
    rescue Date::Error
      raise ParseError, "invalid date"
    end

    private

    def excel_serial_date(value)
      serial = BigDecimal(value.to_s)
      raise ParseError, "invalid Excel serial date" if serial <= 0

      EXCEL_EPOCH + serial.to_i
    rescue ArgumentError
      raise ParseError, "invalid Excel serial date"
    end
  end
end
