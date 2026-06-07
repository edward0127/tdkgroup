require "bigdecimal"

module BasImports
  class AmountParser
    class ParseError < StandardError; end

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

      string = value.to_s.strip
      return nil if string.blank?

      negative_parentheses = string.match?(/\A\(.*\)\z/)
      string = string[1..-2].strip if negative_parentheses
      string = string.delete("$,").gsub(/\s+/, "")
      string = string.delete_prefix("+")

      unless string.match?(/\A-?\d+(\.\d+)?\z/)
        raise ParseError, "invalid amount"
      end

      amount = BigDecimal(string)
      negative_parentheses ? -amount.abs : amount
    end
  end
end
