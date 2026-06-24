require "bigdecimal"
require "date"
require "pdf/reader"

module BasTdk
  class PdfStatementParser
    class ParseError < StandardError; end

    UNREADABLE_PDF_MESSAGE = "This PDF appears to be image-based or does not contain a readable transaction table. Please upload the original bank PDF with selectable text, or upload XLSX.".freeze
    SHEET_NAME = "PDF transaction table".freeze
    BASE_HEADERS = [ "Date", "Category", "Amount", "GST", "Description", "Details" ].freeze
    MONTHS = {
      "JAN" => 1, "JANUARY" => 1,
      "FEB" => 2, "FEBRUARY" => 2,
      "MAR" => 3, "MARCH" => 3,
      "APR" => 4, "APRIL" => 4,
      "MAY" => 5,
      "JUN" => 6, "JUNE" => 6,
      "JUL" => 7, "JULY" => 7,
      "AUG" => 8, "AUGUST" => 8,
      "SEP" => 9, "SEPT" => 9, "SEPTEMBER" => 9,
      "OCT" => 10, "OCTOBER" => 10,
      "NOV" => 11, "NOVEMBER" => 11,
      "DEC" => 12, "DECEMBER" => 12
    }.freeze
    MONTH_PATTERN = MONTHS.keys.sort_by(&:length).reverse.join("|")
    DATE_START_PATTERN = /
      \A\s*
      (?<date>
        \d{1,2}[\/-]\d{1,2}[\/-](?:\d{2}|\d{4}) |
        \d{4}-\d{1,2}-\d{1,2} |
        \d{1,2}\s+(?:#{MONTH_PATTERN})(?:\s+\d{2,4})?
      )
      \b
    /ix
    AMOUNT_PATTERN = /
      (?<![A-Za-z0-9])
      \$?
      \(?
      -?
      (?:
        \d{1,3}(?:,\d{3})+ |
        \d+
      )
      \.\d{2}
      \)?
      (?![A-Za-z0-9])
    /x
    EXTRACTED_BLANK_TOKEN_PATTERN = /(?<![A-Za-z0-9])blank(?![A-Za-z0-9])/i
    BLANK_TOKEN_SOURCE = EXTRACTED_BLANK_TOKEN_PATTERN.source
    AMOUNT_TOKEN_SOURCE = AMOUNT_PATTERN.source
    ANZ_WITHDRAWAL_BLANK_DEPOSIT_PATTERN = Regexp.new(
      "(?<withdrawal>#{AMOUNT_TOKEN_SOURCE})\\s+#{BLANK_TOKEN_SOURCE}\\s+(?<balance>#{AMOUNT_TOKEN_SOURCE})(?:\\s+#{BLANK_TOKEN_SOURCE})*\\s*\\z",
      Regexp::IGNORECASE | Regexp::EXTENDED
    )
    ANZ_BLANK_WITHDRAWAL_DEPOSIT_PATTERN = Regexp.new(
      "#{BLANK_TOKEN_SOURCE}\\s+(?<deposit>#{AMOUNT_TOKEN_SOURCE})\\s+(?<balance>#{AMOUNT_TOKEN_SOURCE})(?:\\s+#{BLANK_TOKEN_SOURCE})*\\s*\\z",
      Regexp::IGNORECASE | Regexp::EXTENDED
    )
    INLINE_STOP_BOUNDARY_PATTERN = /\bTOTALS?\s+AT\s+END\s+OF\s+(?:PAGE|PERIOD)\b/i
    TABLE_STOP_NORMALIZED_PATTERN = /
      \b(
        closing\s+balance |
        balance\s+carried\s+forward |
        convenience\s+at\s+your\s+fingertips |
        transaction\s+fee\s+summary |
        fee\s+summary |
        fees?\s+and\s+charges\s+summary |
        more\s+information |
        important\s+information |
        thank\s+you\s+for\s+banking |
        use\s+online\s+mobile\s+or\s+tablet\s+banking |
        to\s+reconcile\s+your\s+transaction\s+fee\s+summary |
        fee\s+s\s+charged\s+to\s+account |
        fees\s+charged\s+to\s+account |
        westpac\s+live\s+telephone\s+banking |
        complaints |
        totals?\s+at\s+end\s+of\s+(page|period) |
        unit\s+volume\s+price\s+fee |
        total\s+electronic\s+credits |
        total\s+electronic\s+debits |
        electronic\s+debits
      )\b
    /ix
    SKIP_LINE_NORMALIZED_PATTERN = /
      \A(
        page\s+\d+ |
        statement\s+opening\s+balance |
        opening\s+balance |
        balance\s+brought\s+forward |
        totals?\s+(debits|credits|withdrawals|deposits) |
        interest\s+rate |
        statement\s+summary |
        account\s+summary
      )\b
    /ix
    NON_TRANSACTION_DESCRIPTION_PATTERN = /
      \A\s*(
        statement\s+opening\s+balance |
        opening\s+balance |
        closing\s+balance |
        totals?\s+at\s+end\s+of\s+(page|period) |
        fee\s+summary |
        transaction\s+fee\s+summary |
        interest\s+rate |
        statement\s+summary |
        unit\s+volume\s+price\s+fee |
        total\s+electronic\s+credits |
        electronic\s+debits
      )\b
    /ix

    ParsedStatement = Struct.new(
      :sheet_name,
      :header_row_number,
      :original_headers,
      :processed_headers,
      :rows,
      keyword_init: true
    )
    HeaderShape = Struct.new(:line_number, :original_headers, :columns, keyword_init: true)
    TransactionBlock = Struct.new(:line_number, :lines, keyword_init: true)

    def initialize(path:)
      @path = path
    end

    def call
      extracted = extract_text
      @statement_periods = extract_statement_periods(extracted.fetch(:text))
      @fallback_years = extracted.fetch(:text).scan(/\b20\d{2}\b/).map(&:to_i).uniq
      lines = extracted.fetch(:text).lines.map.with_index(1) do |line, line_number|
        original_raw = line.to_s.delete("\r").chomp
        { raw: scrub_extracted_blank_tokens(original_raw), original_raw: original_raw, line_number: line_number }
      end
      header_shape = detect_header_shape(lines)
      raise ParseError, UNREADABLE_PDF_MESSAGE if header_shape.blank?

      blocks = transaction_blocks(lines, header_shape)
      rows = parsed_rows(blocks, header_shape)
      raise ParseError, UNREADABLE_PDF_MESSAGE if rows.blank?

      processed_headers = BASE_HEADERS.dup
      processed_headers << "Balance" if header_shape.columns.key?(:balance) || rows.any? { |row| row.fetch(:data)["Balance"].present? }
      rows.each { |row| processed_headers.each { |header| row.fetch(:data)[header] = "" unless row.fetch(:data).key?(header) } }

      ParsedStatement.new(
        sheet_name: SHEET_NAME,
        header_row_number: header_shape.line_number,
        original_headers: header_shape.original_headers,
        processed_headers: processed_headers,
        rows: rows
      )
    rescue PDF::Reader::EncryptedPDFError, PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError
      raise ParseError, UNREADABLE_PDF_MESSAGE
    end

    private

    attr_reader :path, :statement_periods, :fallback_years

    def extract_text
      File.open(path, "rb") do |file|
        reader = PDF::Reader.new(file)
        text = reader.pages.map(&:text).join("\n\n").scrub
        raise ParseError, UNREADABLE_PDF_MESSAGE if text.squish.blank?

        { text: text, page_count: reader.page_count }
      end
    end

    def detect_header_shape(lines)
      candidates = lines.filter_map do |line|
        score = header_score(line.fetch(:raw))
        next if score.zero?

        [ score, line.fetch(:line_number), header_shape(line) ]
      end

      candidates.max_by { |score, line_number, _shape| [ score, -line_number ] }&.last
    end

    def header_score(raw_line)
      normalized = normalize(raw_line)
      return 0 unless normalized.include?("date")
      return 0 unless description_header?(normalized)

      amount_score = 0
      amount_score += 10 if debit_header?(normalized)
      amount_score += 10 if credit_header?(normalized)
      amount_score += 6 if balance_header?(normalized)
      return 0 if amount_score.zero?

      20 + amount_score
    end

    def header_shape(line)
      raw = line.fetch(:raw)
      columns = {}
      columns[:date] = column(:date, raw, /\b(transaction\s+date|effective\s+date|date)\b/i)
      columns[:description] = column(:description, raw, /\b(transaction\s+description|transaction\s+details|description|details)\b/i)
      columns[:debit] = column(:debit, raw, /\b(debit\s+amount|withdrawals?(?:\s+\(\$\))?|debit)\b/i)
      columns[:credit] = column(:credit, raw, /\b(credit\s+amount|deposits?(?:\s+\(\$\))?|credit)\b/i)
      columns[:balance] = column(:balance, raw, /\b(running\s+balance(?:\s+\(\$\))?|balance(?:\s+\(\$\))?)\b/i)
      columns.compact!

      HeaderShape.new(
        line_number: line.fetch(:line_number),
        original_headers: original_headers(columns),
        columns: columns
      )
    end

    def column(key, raw, pattern)
      match = raw.match(pattern)
      return if match.blank?

      {
        key: key,
        label: match[0].squish,
        start: match.begin(0)
      }
    end

    def original_headers(columns)
      [ :date, :description, :debit, :credit, :balance ].filter_map do |key|
        columns.dig(key, :label)
      end
    end

    def transaction_blocks(lines, header_shape)
      blocks = []
      current = nil
      in_table = false

      lines.each do |line|
        raw = line.fetch(:raw)

        if header_score(raw).positive?
          blocks << current if current.present?
          current = nil
          in_table = true
          next
        end

        next unless in_table

        line, stop_after_line = truncate_inline_stop_boundary(line)
        raw = line.fetch(:raw)
        squished = raw.squish

        if squished.blank?
          if stop_after_line
            blocks << current if current.present?
            current = nil
            in_table = false
          end
          next
        end

        if table_stop_line?(squished)
          blocks << current if current.present?
          current = nil
          in_table = false
          next
        end

        next if skip_line?(squished)

        if raw.match?(DATE_START_PATTERN)
          if non_transaction_dated_line?(raw)
            blocks << current if current.present?
            current = nil
            next
          end

          blocks << current if current.present?
          current = TransactionBlock.new(line_number: line.fetch(:line_number), lines: [ line ])
        elsif current.present? && continuation_line?(raw, header_shape)
          current.lines << line
        end

        if stop_after_line
          blocks << current if current.present?
          current = nil
          in_table = false
        end
      end

      blocks << current if current.present?
      blocks
    end

    def continuation_line?(raw, header_shape)
      squished = raw.squish
      return false if table_stop_line?(squished)
      return false if skip_line?(squished)
      return true if header_shape.columns.dig(:description, :start).blank?

      first_text_index = raw.index(/\S/)
      return true if first_text_index.blank?

      first_text_index >= [ header_shape.columns.dig(:description, :start).to_i - 8, 0 ].max ||
        raw.scan(AMOUNT_PATTERN).any?
    end

    def parsed_rows(blocks, header_shape)
      blocks.filter_map.with_index(1) do |block, position|
        parsed_row(block, header_shape, position)
      end
    end

    def parsed_row(block, header_shape, position)
      first_line = block.lines.first.fetch(:raw)
      date_match = first_line.match(DATE_START_PATTERN)
      return if date_match.blank?

      date = parse_date(date_match[:date])
      return if date.blank?

      assignments = assign_amounts(block, header_shape)
      amount = transaction_amount(assignments)
      return if amount.blank?

      description = description_from_block(block, date_match.end(0), assignments)
      return if description.blank? || non_transaction_description?(description)

      data = {
        "Date" => date.iso8601,
        "Category" => "",
        "Amount" => serialize_amount(amount),
        "GST" => "",
        "Description" => description,
        "Details" => ""
      }
      data["Balance"] = serialize_amount(assignments[:balance]) if assignments[:balance].present?

      {
        position: position,
        source_row_number: block.line_number,
        data: data
      }
    end

    def assign_amounts(block, header_shape)
      candidates = amount_candidates(block)
      return {} if candidates.blank?

      return assign_anz_business_extra_amounts(block, header_shape, candidates) if anz_business_extra_header?(header_shape)

      assignments = assign_amounts_by_position(candidates, header_shape)
      assignments = assign_amounts_by_fallback(candidates, header_shape) if transaction_amount(assignments).blank?
      assignments
    end

    def assign_anz_business_extra_amounts(block, header_shape, candidates)
      return {} unless header_shape.columns.key?(:balance)
      return {} if candidates.size < 2

      balance_candidate = candidates.last
      transaction_candidates = candidates[0...-1]
      assignments = { balance: balance_candidate.fetch(:amount) }
      return assignments unless transaction_candidates.one?

      transaction_candidate = transaction_candidates.first
      amount_column = anz_blank_marker_column(block, transaction_candidate, balance_candidate) ||
        strict_amount_column(transaction_candidate, header_shape, [ :debit, :credit ])
      return assignments if amount_column.blank?

      assignments[amount_column] = transaction_candidate.fetch(:amount)
      assignments
    end

    def amount_candidates(block)
      block.lines.flat_map.with_index do |line, index|
        raw = line.fetch(:raw)
        raw.to_enum(:scan, AMOUNT_PATTERN).map do
          match = Regexp.last_match
          amount = parse_amount(match[0])
          next if amount.blank?

          {
            line_index: index,
            line_number: line.fetch(:line_number),
            start: match.begin(0),
            end: match.end(0),
            raw: match[0],
            amount: amount
          }
        end
      end.compact
    end

    def assign_amounts_by_position(candidates, header_shape)
      amount_columns = [ :debit, :credit, :balance ].filter_map do |key|
        column = header_shape.columns[key]
        next if column.blank?

        [ key, column.fetch(:start).to_i ]
      end
      return {} if amount_columns.blank?

      assignments = {}
      candidate_by_assignment = {}
      remaining_candidates = candidates

      if header_shape.columns.key?(:balance) && candidates.size >= 2
        assignments[:balance] = candidates.last.fetch(:amount)
        remaining_candidates = candidates[0...-1]
        amount_columns = amount_columns.reject { |key, _start| key == :balance }
      end
      return assignments if amount_columns.blank?

      remaining_candidates.each do |candidate|
        key, distance = closest_amount_column(candidate, amount_columns)
        next if key.blank? || distance.blank? || distance > 24

        existing = candidate_by_assignment[key]
        if existing.blank? || distance < existing.fetch(:distance)
          assignments[key] = candidate.fetch(:amount)
          candidate_by_assignment[key] = candidate.merge(distance: distance)
        end
      end

      assignments
    end

    def closest_amount_column(candidate, amount_columns)
      amount_columns.map do |key, start|
        [ key, (candidate.fetch(:start) - start).abs ]
      end.min_by(&:second)
    end

    def strict_amount_column(candidate, header_shape, keys, max_distance: 24)
      amount_columns = keys.filter_map do |key|
        column = header_shape.columns[key]
        next if column.blank?

        [ key, column.fetch(:start).to_i ]
      end
      return if amount_columns.blank?

      key, distance = closest_amount_column(candidate, amount_columns)
      return if key.blank? || distance.blank? || distance > max_distance

      key
    end

    def assign_amounts_by_fallback(candidates, header_shape)
      assignments = {}
      if header_shape.columns.key?(:balance) && candidates.size >= 2
        assignments[:balance] = candidates.last.fetch(:amount)
        transaction_candidate = candidates[-2]
      else
        transaction_candidate = candidates.last
      end

      if header_shape.columns.key?(:debit) && !header_shape.columns.key?(:credit)
        assignments[:debit] = transaction_candidate.fetch(:amount)
      elsif header_shape.columns.key?(:credit) && !header_shape.columns.key?(:debit)
        assignments[:credit] = transaction_candidate.fetch(:amount)
      elsif header_shape.columns.key?(:debit) && header_shape.columns.key?(:credit)
        nearest_key, = closest_amount_column(
          transaction_candidate,
          [ :debit, :credit ].map { |key| [ key, header_shape.columns.dig(key, :start).to_i ] }
        )
        assignments[nearest_key || :amount] = transaction_candidate.fetch(:amount)
      else
        assignments[:amount] = transaction_candidate.fetch(:amount)
      end

      assignments
    end

    def transaction_amount(assignments)
      return assignments[:credit].abs if assignments[:credit].present?
      return -assignments[:debit].abs if assignments[:debit].present?
      return assignments[:amount] if assignments[:amount].present?

      nil
    end

    def description_from_block(block, first_line_date_end, assignments)
      assigned_candidates = assigned_amount_candidates(block, assignments)

      block.lines.map.with_index do |line, index|
        raw = line.fetch(:raw).dup
        start_index = index.zero? ? first_line_date_end : 0
        assigned_candidates.select { |candidate| candidate.fetch(:line_index) == index }.each do |candidate|
          raw[candidate.fetch(:start)...candidate.fetch(:end)] = " " * (candidate.fetch(:end) - candidate.fetch(:start))
        end
        raw[start_index..].to_s.squish
      end.reject(&:blank?).join(" ").squish
    end

    def assigned_amount_candidates(block, assignments)
      return [] if assignments.blank?

      candidates = amount_candidates(block)
      assigned_amounts = assignments.slice(:debit, :credit, :balance, :amount).values.compact.map { |amount| amount.round(2) }
      candidates.select { |candidate| assigned_amounts.include?(candidate.fetch(:amount).round(2)) }
    end

    def scrub_extracted_blank_tokens(value)
      value.to_s.gsub(EXTRACTED_BLANK_TOKEN_PATTERN, " ")
    end

    def truncate_inline_stop_boundary(line)
      raw = line.fetch(:raw).to_s
      match = raw.match(INLINE_STOP_BOUNDARY_PATTERN)
      return [ line, false ] if match.blank? || match.begin(0).zero?

      original_raw = line.fetch(:original_raw).to_s
      original_match = original_raw.match(INLINE_STOP_BOUNDARY_PATTERN)
      [
        line.merge(
          raw: raw[0...match.begin(0)].to_s.rstrip,
          original_raw: if original_match.present? && original_match.begin(0).positive?
            original_raw[0...original_match.begin(0)].to_s.rstrip
          else
            original_raw
          end
        ),
        true
      ]
    end

    def table_stop_line?(line)
      normalize(line).match?(TABLE_STOP_NORMALIZED_PATTERN)
    end

    def skip_line?(line)
      normalize(line).match?(SKIP_LINE_NORMALIZED_PATTERN)
    end

    def non_transaction_dated_line?(raw)
      date_match = raw.match(DATE_START_PATTERN)
      return false if date_match.blank?

      non_transaction_description?(raw[date_match.end(0)..])
    end

    def non_transaction_description?(description)
      description.to_s.match?(NON_TRANSACTION_DESCRIPTION_PATTERN) ||
        normalize(description).match?(TABLE_STOP_NORMALIZED_PATTERN)
    end

    def anz_business_extra_header?(header_shape)
      debit_label = normalize(header_shape.columns.dig(:debit, :label))
      credit_label = normalize(header_shape.columns.dig(:credit, :label))
      description_label = normalize(header_shape.columns.dig(:description, :label))

      debit_label.include?("withdrawal") &&
        credit_label.include?("deposit") &&
        description_label.include?("details")
    end

    def anz_blank_marker_column(block, transaction_candidate, balance_candidate)
      text = block.lines.map { |line| line.fetch(:original_raw).to_s }.join(" ").squish

      withdrawal_match = text.match(ANZ_WITHDRAWAL_BLANK_DEPOSIT_PATTERN)
      if withdrawal_match.present? &&
          same_candidate_amount?(withdrawal_match[:withdrawal], transaction_candidate) &&
          same_candidate_amount?(withdrawal_match[:balance], balance_candidate)
        return :debit
      end

      deposit_match = text.match(ANZ_BLANK_WITHDRAWAL_DEPOSIT_PATTERN)
      if deposit_match.present? &&
          same_candidate_amount?(deposit_match[:deposit], transaction_candidate) &&
          same_candidate_amount?(deposit_match[:balance], balance_candidate)
        return :credit
      end

      nil
    end

    def same_candidate_amount?(raw_amount, candidate)
      amount = parse_amount(raw_amount)
      amount.present? && amount.round(2) == candidate.fetch(:amount).round(2)
    end

    def parse_date(value)
      text = value.to_s.squish.upcase

      if text.match?(/\A\d{4}-\d{1,2}-\d{1,2}\z/)
        return Date.strptime(text, "%Y-%m-%d")
      end

      if text.match?(/\A\d{1,2}[\/-]\d{1,2}[\/-]\d{4}\z/)
        return Date.strptime(text.tr("-", "/"), "%d/%m/%Y")
      end

      if text.match?(/\A\d{1,2}[\/-]\d{1,2}[\/-]\d{2}\z/)
        return Date.strptime(text.tr("-", "/"), "%d/%m/%y")
      end

      month_match = text.match(/\A(?<day>\d{1,2})\s+(?<month>#{MONTH_PATTERN})(?:\s+(?<year>\d{2,4}))?\z/i)
      return if month_match.blank?

      day = month_match[:day].to_i
      month = MONTHS.fetch(month_match[:month].upcase)
      year = normalized_year(month_match[:year]) || inferred_year(day, month)
      return if year.blank?

      Date.new(year, month, day)
    rescue ArgumentError
      nil
    end

    def extract_statement_periods(text)
      text.lines.filter_map do |line|
        dates = month_name_dates(line)
        next [ dates.first, dates.second ] if dates.size >= 2

        slash_dates = slash_dates(line)
        [ slash_dates.first, slash_dates.second ] if slash_dates.size >= 2
      end
    end

    def month_name_dates(line)
      line.to_s.scan(/\b(\d{1,2})\s+(#{MONTH_PATTERN})\s+(\d{4})\b/i).filter_map do |day, month_name, year|
        Date.new(year.to_i, MONTHS.fetch(month_name.upcase), day.to_i)
      rescue ArgumentError
        nil
      end
    end

    def slash_dates(line)
      line.to_s.scan(/\b(\d{1,2})[\/-](\d{1,2})[\/-](\d{2,4})\b/).filter_map do |day, month, year|
        Date.new(normalized_year(year), month.to_i, day.to_i)
      rescue ArgumentError
        nil
      end
    end

    def inferred_year(day, month)
      candidates = @statement_periods.to_a.flat_map do |start_date, end_date|
        [ start_date.year, end_date.year ].uniq.filter_map do |year|
          Date.new(year, month, day)
        rescue ArgumentError
          nil
        end.select { |date| date.between?(start_date, end_date) }
      end
      return candidates.first.year if candidates.any?
      return fallback_years.first if fallback_years.one?

      nil
    end

    def normalized_year(value)
      return if value.blank?

      year = value.to_i
      return year if value.to_s.length == 4

      year >= 70 ? 1900 + year : 2000 + year
    end

    def parse_amount(value)
      text = value.to_s.strip
      negative = text.include?("-") || text.start_with?("(")
      normalized = text.delete("$").delete(",").delete("(").delete(")").delete("-").strip
      decimal = BigDecimal(normalized)
      negative ? -decimal.abs : decimal
    rescue ArgumentError
      nil
    end

    def serialize_amount(decimal)
      return "" if decimal.blank?

      rounded = decimal.round(2)
      whole, fraction = rounded.to_s("F").split(".", 2)
      "#{whole}.#{fraction.to_s.ljust(2, "0").first(2)}"
    end

    def normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
    end

    def description_header?(normalized)
      normalized.match?(/\b(transaction description|transaction details|description|details)\b/)
    end

    def debit_header?(normalized)
      normalized.match?(/\b(debit|withdrawal|withdrawals|debit amount)\b/)
    end

    def credit_header?(normalized)
      normalized.match?(/\b(credit|deposit|deposits|credit amount)\b/)
    end

    def balance_header?(normalized)
      normalized.match?(/\b(balance|running balance)\b/)
    end
  end
end
