require "bigdecimal"

module BasPdfBankStatements
  class TransactionParser
    Result = Data.define(:rows, :row_errors, :detected_bank_name)

    DATE_PATTERN = /
      (?<date>
        \d{1,2}[\/-]\d{1,2}[\/-]\d{4} |
        \d{4}-\d{2}-\d{2}
      )
    /x
    AMOUNT_PATTERN = /\(?-?\$?\d{1,3}(?:,\d{3})*(?:\.\d{2})\)?|\(?-?\$?\d+(?:\.\d{2})\)?/.freeze
    IGNORE_LINE_PATTERN = /
      \A(
        page\s+\d+ |
        date\s+description |
        transaction\s+date |
        opening\s+balance |
        closing\s+balance |
        balance\s+(brought|carried)\s+forward |
        total\s+(debits|credits)
      )
    /ix

    BANK_NAME_PATTERNS = {
      "Commonwealth Bank" => /commonwealth|commbank|\bcba\b/i,
      "ANZ" => /\banz\b|australia and new zealand/i,
      "NAB" => /\bnab\b|national australia bank/i,
      "Westpac" => /westpac/i,
      "Macquarie Bank" => /macquarie/i,
      "Bendigo Bank" => /bendigo/i
    }.freeze

    def initialize(text:)
      @text = text.to_s
    end

    def call
      rows = transaction_blocks.map.with_index(1) do |block, index|
        parse_block(block, index)
      end

      Result.new(rows: rows, row_errors: [], detected_bank_name: detected_bank_name)
    end

    private

    attr_reader :text

    def transaction_blocks
      blocks = []
      current = nil

      candidate_lines.each do |line|
        if line.match?(/\A\s*#{DATE_PATTERN}/x)
          blocks << current if current.present?
          current = line.dup
        elsif current.present?
          current = "#{current} #{line}"
        end
      end

      blocks << current if current.present?
      blocks
    end

    def candidate_lines
      text.lines.map { |line| line.to_s.squish }.reject do |line|
        line.blank? || line.match?(IGNORE_LINE_PATTERN)
      end
    end

    def parse_block(block, row_number)
      match = block.match(/\A\s*#{DATE_PATTERN}\s+(?<rest>.+)\z/x)
      return blank_row(row_number, "Could not find transaction date.") if match.blank?

      raw_date = match[:date]
      rest = match[:rest].to_s.squish
      amount_matches = rest.to_enum(:scan, AMOUNT_PATTERN).map do
        Regexp.last_match
      end
      amount_infos = amount_matches.map { |amount_match| amount_info(rest, amount_match) }
      amount_info = amount_infos[-2] || amount_infos[-1]
      balance_info = amount_infos.size >= 2 ? amount_infos[-1] : nil

      description_end = amount_info ? amount_info.fetch(:begin) : rest.length
      description = rest[0...description_end].to_s.squish

      debit, credit, amount = debit_credit_amount(amount_info, rest)

      {
        "row_number" => row_number,
        "transaction_date" => normalize_date(raw_date),
        "description" => description,
        "details" => nil,
        "reference" => extract_reference(description),
        "debit" => serialize_amount(debit),
        "credit" => serialize_amount(credit),
        "amount" => serialize_amount(amount),
        "balance" => serialize_amount(balance_info&.fetch(:amount)),
        "bank_account_name" => nil
      }
    end

    def amount_info(rest, match)
      raw = match[0]
      prefix = rest[[ match.begin(0) - 8, 0 ].max...match.begin(0)].to_s
      suffix = rest[match.end(0)...[ match.end(0) + 8, rest.length ].min].to_s

      {
        raw: raw,
        amount: parse_amount(raw),
        begin: match.begin(0),
        end: match.end(0),
        debit_hint: raw.include?("-") || raw.start_with?("(") || prefix.match?(/\bDR\s*\z/i) || suffix.match?(/\A\s*DR\b/i),
        credit_hint: prefix.match?(/\bCR\s*\z/i) || suffix.match?(/\A\s*CR\b/i)
      }
    end

    def debit_credit_amount(info, rest)
      return [ nil, nil, nil ] if info.blank?

      amount = info.fetch(:amount)
      debit_hint = info.fetch(:debit_hint) || rest.match?(/\b(debit|withdrawal|payment)\b/i)
      credit_hint = info.fetch(:credit_hint) || rest.match?(/\b(credit|deposit|receipt)\b/i)

      if credit_hint && !debit_hint
        [ nil, amount.abs, amount.abs ]
      elsif debit_hint || amount.negative?
        [ amount.abs, nil, -amount.abs ]
      else
        [ nil, nil, amount ]
      end
    end

    def detected_bank_name
      BANK_NAME_PATTERNS.find { |_name, pattern| text.lines.first(30).join(" ").match?(pattern) }&.first
    end

    def normalize_date(value)
      BasImports::DateParser.parse!(value).to_fs(:db)
    rescue BasImports::DateParser::ParseError
      value.to_s
    end

    def parse_amount(value)
      BasImports::AmountParser.parse!(value)
    rescue BasImports::AmountParser::ParseError
      nil
    end

    def serialize_amount(value)
      return nil if value.nil?

      whole, fraction = value.round(2).to_s("F").split(".", 2)
      "#{whole}.#{fraction.to_s.ljust(2, "0")}"
    end

    def extract_reference(description)
      description.to_s[/\b(?:ref|reference)\s*[:#-]?\s*([A-Z0-9-]{3,})\b/i, 1]
    end

    def blank_row(row_number, message)
      {
        "row_number" => row_number,
        "transaction_date" => nil,
        "description" => nil,
        "amount" => nil,
        "warnings" => [ message ]
      }
    end
  end
end
