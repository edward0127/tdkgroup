require "bigdecimal"
require "date"
require "pdf/reader"

module BasTdk
  class PdfStatementParser
    class ParseError < StandardError
      OCR_ELIGIBLE_CODES = %i[no_readable_text no_transaction_table].freeze

      attr_reader :code

      def initialize(message = nil, code: :unknown)
        @code = code
        super(message || BasTdk::PdfStatementParser::UNREADABLE_PDF_MESSAGE)
      end

      def ocr_eligible?
        OCR_ELIGIBLE_CODES.include?(code)
      end
    end

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
    MONTH_NAME_DATE_CONTINUATION_PATTERN = /\A\s*\d{1,2}\s+(?:#{MONTH_PATTERN})\s+\d{2,4}\b/i
    OCR_CURRENCY_MARKER_SOURCE = "\\$\\u{00A7}".freeze
    AMOUNT_NUMBER_SOURCE = "(?:\\d{1,3}(?:,\\d{3})+|\\d+)\\.\\d{2}".freeze
    OCR_AMOUNT_NUMBER_SOURCE = "(?:\\d{1,3}(?:,\\d{3})+|\\d+)\\.\\d{2,4}".freeze
    AMOUNT_PATTERN = /
      (?<![A-Za-z0-9])
      (?:
        \(\s*-?\s*[#{OCR_CURRENCY_MARKER_SOURCE}]?\s*#{AMOUNT_NUMBER_SOURCE}\s*\) |
        -\s*[#{OCR_CURRENCY_MARKER_SOURCE}]?\s*#{AMOUNT_NUMBER_SOURCE} |
        [#{OCR_CURRENCY_MARKER_SOURCE}]\s*-?\s*#{AMOUNT_NUMBER_SOURCE} |
        #{AMOUNT_NUMBER_SOURCE}
      )
      (?![A-Za-z0-9])
    /x
    OCR_AMOUNT_PATTERN = /
      (?<![A-Za-z0-9])
      (?:
        \(\s*-?\s*[#{OCR_CURRENCY_MARKER_SOURCE}]?\s*#{OCR_AMOUNT_NUMBER_SOURCE}\s*\) |
        -\s*[#{OCR_CURRENCY_MARKER_SOURCE}]?\s*#{OCR_AMOUNT_NUMBER_SOURCE} |
        [#{OCR_CURRENCY_MARKER_SOURCE}]\s*-?\s*#{OCR_AMOUNT_NUMBER_SOURCE} |
        #{OCR_AMOUNT_NUMBER_SOURCE}
      )
      (?![A-Za-z0-9])
    /x
    OCR_DESCRIPTION_NOISE_TOKEN_PATTERN = /\A(?:-?[#{OCR_CURRENCY_MARKER_SOURCE}]+|[^\p{Alnum}]+)\z/u
    OCR_DESCRIPTION_EDGE_NOISE_PATTERN = /\A[_~|"'\\\/\[\]\(\).:;]+|[_~|"'\\\/\[\]\(\).:;]+\z/
    OCR_SPLIT_UPPERCASE_COMPLETIONS = %w[VIC NSW QLD ACT TAS].freeze
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
    INLINE_STOP_BOUNDARY_PATTERN = /
      (?:
        \b(?:https?:\/\/\S+|www\.\S+) |
        \bprinted\s*: |
        \bpage\s+\d+\s+of\s+\d+\b |
        \b(
        closing\s+balance |
        balance\s+carried\s+forward |
        convenience\s+at\s+your\s+fingertips |
        transaction\s+fee\s+summary |
        fees?\s+and\s+charges\s+summary |
        gsso |
        intranet |
        more\s+information |
        need\s+help |
        contact\s+us |
        for\s+more\s+information |
        visit\s+westpac |
        terms\s+and\s+conditions |
        privacy |
        important\s+information |
        thank\s+you\s+for\s+banking |
        things\s+you\s+should\s+know |
        running\s+balance\s+means |
        this\s+page\s+is\s+current\s+as\s+at |
        not\s+an\s+official\s+statement |
        service\s+online |
        service\s+online\s+page |
        use\s+online\s+mobile\s+or\s+tablet\s+banking |
        to\s+reconcile\s+your\s+transaction\s+fee\s+summary |
        fees?\s+charged |
        complaints |
        totals?\s+at\s+end\s+of\s+(?:page|period)
        )\b
      )
    /ix
    TABLE_STOP_NORMALIZED_PATTERN = /
      \b(
        https? |
        www |
        closing\s+balance |
        balance\s+carried\s+forward |
        convenience\s+at\s+your\s+fingertips |
        transaction\s+fee\s+summary |
        fee\s+summary |
        fees?\s+and\s+charges\s+summary |
        gsso |
        intranet |
        more\s+information |
        need\s+help |
        contact\s+us |
        for\s+more\s+information |
        visit\s+westpac |
        terms\s+and\s+conditions |
        privacy |
        important\s+information |
        thank\s+you\s+for\s+banking |
        things\s+you\s+should\s+know |
        running\s+balance\s+means |
        this\s+page\s+is\s+current\s+as\s+at |
        not\s+an\s+official\s+statement |
        printed |
        service\s+online |
        service\s+online\s+page |
        page\s+\d+\s+of |
        use\s+online\s+mobile\s+or\s+tablet\s+banking |
        to\s+reconcile\s+your\s+transaction\s+fee\s+summary |
        fee\s+s\s+charged\s+to\s+account |
        fees\s+charged\s+to\s+account |
        fees?\s+charged |
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
        https? |
        www |
        gsso |
        intranet |
        printed |
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
    SCANNED_CREDIT_DESCRIPTION_PATTERN = /
      \b(
        deposit |
        deposit\s+online |
        transfer\s+deposit |
        direct\s+credit |
        transfer\s+from |
        credit |
        osko\s+deposit |
        payid\s+credit |
        cash\s+deposit
      )\b
    /ix
    SCANNED_DEBIT_DESCRIPTION_PATTERN = /
      \b(
        withdrawal |
        withdraw |
        monthly\s+plan\s+fee |
        line\s+fee |
        overdrawn\s+fee |
        fee |
        charge |
        debit |
        direct\s+debit |
        eftpos |
        visa |
        mastercard |
        card |
        atm |
        bpay |
        payment\s+to |
        payment\s+by\s+authority |
        transfer\s+to |
        internet\s+banking\s+withdrawal |
        purchase |
        interest |
        payroll
      )\b
    /ix
    SCANNED_GENERIC_DEBIT_DESCRIPTION_PATTERN = /
      \b(
        osko\s+payment
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

    def initialize(path: nil, text: nil, source_name: nil)
      raise ArgumentError, "path or text is required" if path.blank? && text.nil?
      raise ArgumentError, "provide path or text, not both" if path.present? && !text.nil?

      @path = path
      @text = text
      @source_name = source_name
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
      raise_parse_error(:no_transaction_table) if header_shape.blank?

      blocks = transaction_blocks(lines, header_shape)
      rows = parsed_rows(blocks, header_shape)
      raise_parse_error(:no_transaction_table) if rows.blank?

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
    rescue PDF::Reader::EncryptedPDFError
      raise_parse_error(:encrypted_pdf)
    rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError
      raise_parse_error(:malformed_pdf)
    end

    private

    attr_reader :path, :text, :source_name, :statement_periods, :fallback_years

    def extract_text
      return extract_supplied_text if text_source?

      File.open(path, "rb") do |file|
        reader = PDF::Reader.new(file)
        text = reader.pages.map(&:text).join("\n\n").scrub
        raise_parse_error(:no_readable_text) if text.squish.blank?

        { text: text, page_count: reader.page_count }
      end
    end

    def extract_supplied_text
      extracted_text = text.to_s.scrub
      raise_parse_error(:no_readable_text) if extracted_text.squish.blank?

      { text: extracted_text, page_count: nil }
    end

    def text_source?
      !text.nil?
    end

    def detect_header_shape(lines)
      candidates = lines.filter_map.with_index do |line, index|
        score = header_score(line.fetch(:raw), bank_context: bank_statement_context?(lines, index))
        next if score.zero?

        [ score, line.fetch(:line_number), header_shape(line) ]
      end

      candidates.max_by { |score, line_number, _shape| [ score, -line_number ] }&.last
    end

    def bank_statement_context?(lines, index)
      context = lines[[ index - 4, 0 ].max..[ index + 2, lines.length - 1 ].min].to_a
      normalize(context.map { |line| line.fetch(:raw) }.join(" ")).match?(/\b(bank|statement|transactions?|account|service online)\b/)
    end

    def header_score(raw_line, bank_context: false)
      normalized = normalize(raw_line)
      return 0 unless normalized.include?("date")

      amount_score = 0
      has_debit = debit_header?(normalized)
      has_credit = credit_header?(normalized)
      has_balance = balance_header?(normalized)
      has_description = description_header?(normalized)
      amount_score += 10 if has_debit
      amount_score += 10 if has_credit
      amount_score += 6 if has_balance
      return 0 if amount_score.zero?
      return 0 unless has_description || (bank_context && has_debit && has_credit && has_balance)

      20 + amount_score + (has_description ? 8 : 0) + (bank_context ? 4 : 0)
    end

    def header_shape(line)
      raw = line.fetch(:raw)
      columns = {}
      columns[:date] = column(:date, raw, /\b(transaction\s+date|effective\s+date|date)\b/i)
      columns[:description] = column(:description, raw, /\b(transaction\s+description|transaction\s+details|description|deseription|details)\b/i)
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

        if header_score(raw, bank_context: true).positive?
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
          if current.present? && date_starting_continuation_line?(raw, header_shape)
            current.lines << line
          elsif non_transaction_dated_line?(raw)
            blocks << current if current.present?
            current = nil
          else
            blocks << current if current.present?
            current = TransactionBlock.new(line_number: line.fetch(:line_number), lines: [ line ])
          end
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
        raw.scan(amount_pattern_for_header(header_shape)).any?
    end

    def date_starting_continuation_line?(raw, header_shape)
      return false unless raw.match?(MONTH_NAME_DATE_CONTINUATION_PATTERN)

      raw.scan(amount_pattern_for_header(header_shape)).blank?
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

      description = description_from_block(block, date_match.end(0), assignments, header_shape)
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
      candidates = amount_candidates(block, amount_pattern: amount_pattern_for_header(header_shape))
      return {} if candidates.blank?

      return assign_anz_business_extra_amounts(block, header_shape, candidates) if anz_business_extra_header?(header_shape)

      if scanned_debit_credit_balance_header?(header_shape)
        scanned_assignments = assign_scanned_debit_credit_balance_amounts(block, header_shape, candidates)
        return scanned_assignments if scanned_assignments.present?
        return {}
      end

      assignments = assign_amounts_by_position(candidates, header_shape)
      assignments = assign_amounts_by_fallback(candidates, header_shape) if transaction_amount(assignments).blank?
      assignments
    end

    def assign_anz_business_extra_amounts(block, header_shape, candidates)
      return {} unless header_shape.columns.key?(:balance)
      return {} if candidates.size < 2

      balance_candidate = candidates.last
      transaction_candidates = candidates[0...-1]
      assignments = { balance: balance_candidate.fetch(:amount), assigned_candidates: [ balance_candidate ] }
      return assignments unless transaction_candidates.one?

      transaction_candidate = transaction_candidates.first
      amount_column = anz_blank_marker_column(block, transaction_candidate, balance_candidate) ||
        strict_amount_column(transaction_candidate, header_shape, [ :debit, :credit ])
      return assignments if amount_column.blank?

      assignments[amount_column] = transaction_candidate.fetch(:amount)
      assignments[:assigned_candidates] << transaction_candidate
      assignments
    end

    def amount_candidates(block, amount_pattern: AMOUNT_PATTERN)
      block.lines.flat_map.with_index do |line, index|
        raw = line.fetch(:raw)
        raw.to_enum(:scan, amount_pattern).map do
          match = Regexp.last_match
          amount = parse_amount(match[0])
          next if amount.blank?

          {
            line_index: index,
            line_number: line.fetch(:line_number),
            line_raw: raw,
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
        candidate_by_assignment[:balance] = candidates.last.merge(distance: 0)
        remaining_candidates = candidates[0...-1]
        amount_columns = amount_columns.reject { |key, _start| key == :balance }
      end
      return assignments if amount_columns.blank?

      remaining_candidates.each do |candidate|
        key, distance = closest_amount_column(candidate, amount_columns)
        next if key.blank? || distance.blank? || distance > 24

        existing = candidate_by_assignment[key]
        if existing.blank? || distance < existing.fetch(:distance)
          candidate_by_assignment[key] = candidate.merge(distance: distance)
        end
      end

      candidate_by_assignment.each do |key, candidate|
        assignments[key] = candidate.fetch(:amount)
      end
      assignments[:assigned_candidates] = candidate_by_assignment.values if assignments.present?
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
        assigned_candidates = [ candidates.last ]
        transaction_candidate = candidates[-2]
      else
        assigned_candidates = []
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

      assignments[:assigned_candidates] = assigned_candidates + [ transaction_candidate ]
      assignments
    end

    def transaction_amount(assignments)
      return assignments[:credit].abs if assignments[:credit].present?
      return -assignments[:debit].abs if assignments[:debit].present?
      return assignments[:amount] if assignments[:amount].present?

      nil
    end

    def scanned_debit_credit_balance_header?(header_shape)
      debit_label = normalize(header_shape.columns.dig(:debit, :label))
      credit_label = normalize(header_shape.columns.dig(:credit, :label))
      balance_label = normalize(header_shape.columns.dig(:balance, :label))

      debit_label.match?(/\b(withdrawal|withdrawals|debit)\b/) &&
        credit_label.match?(/\b(deposit|deposits|credit)\b/) &&
        balance_label.match?(/\b(running balance|balance)\b/)
    end

    def assign_scanned_debit_credit_balance_amounts(block, header_shape, candidates)
      return {} unless header_shape.columns.key?(:balance)
      return {} if candidates.size < 2

      balance_candidate = candidates.last
      transaction_candidate = candidates[0...-1].last
      direction = reliable_scanned_amount_column(transaction_candidate, header_shape)
      description = description_text_without_amounts(block, candidates)
      direction ||= scanned_transaction_direction(description)
      return {} if direction.blank?

      {
        direction => transaction_candidate.fetch(:amount),
        balance: balance_candidate.fetch(:amount),
        assigned_candidates: [ transaction_candidate, balance_candidate ]
      }
    end

    def reliable_scanned_amount_column(candidate, header_shape)
      return unless candidate.fetch(:line_index).zero?
      return unless amount_column_spacing_reliable?(candidate)

      amount_columns = [ :debit, :credit ].filter_map do |key|
        column = header_shape.columns[key]
        next if column.blank?

        [ key, column.fetch(:start).to_i ]
      end
      return if amount_columns.size < 2

      distances = amount_columns.map { |key, start| [ key, (candidate.fetch(:start) - start).abs ] }.sort_by(&:second)
      nearest_key, nearest_distance = distances.first
      next_distance = distances.second&.second
      return if nearest_distance.blank? || nearest_distance > 20
      return if next_distance.present? && (next_distance - nearest_distance) < 8

      nearest_key
    end

    def amount_column_spacing_reliable?(candidate)
      raw = candidate.fetch(:line_raw).to_s
      raw[0...candidate.fetch(:start)].to_s.match?(/\s{2,}\z/)
    end

    def scanned_transaction_direction(description)
      credit = description.match?(SCANNED_CREDIT_DESCRIPTION_PATTERN)
      debit = description.match?(SCANNED_DEBIT_DESCRIPTION_PATTERN)
      debit ||= description.match?(SCANNED_GENERIC_DEBIT_DESCRIPTION_PATTERN) unless credit
      return if credit && debit
      return :credit if credit
      return :debit if debit

      nil
    end

    def amount_pattern_for_header(header_shape)
      scanned_debit_credit_balance_header?(header_shape) ? OCR_AMOUNT_PATTERN : AMOUNT_PATTERN
    end

    def description_text_without_amounts(block, candidates)
      first_line_date_end = block.lines.first.fetch(:raw).match(DATE_START_PATTERN)&.end(0).to_i

      block.lines.map.with_index do |line, index|
        raw = line.fetch(:raw).dup
        start_index = index.zero? ? first_line_date_end : 0
        candidates.select { |candidate| candidate.fetch(:line_index) == index }.each do |candidate|
          raw[candidate.fetch(:start)...candidate.fetch(:end)] = " " * (candidate.fetch(:end) - candidate.fetch(:start))
        end
        raw[start_index..].to_s.squish
      end.reject(&:blank?).join(" ").squish
    end

    def description_from_block(block, first_line_date_end, assignments, header_shape)
      assigned_candidates = assigned_amount_candidates(block, assignments)

      fragments = block.lines.map.with_index do |line, index|
        raw = line.fetch(:raw).dup
        start_index = index.zero? ? first_line_date_end : 0
        assigned_candidates.select { |candidate| candidate.fetch(:line_index) == index }.each do |candidate|
          raw[candidate.fetch(:start)...candidate.fetch(:end)] = " " * (candidate.fetch(:end) - candidate.fetch(:start))
        end
        raw[start_index..].to_s.squish
      end.reject(&:blank?)

      description = join_description_fragments(fragments)

      ocr_description_cleanup_header?(header_shape) ? clean_ocr_description(description) : description
    end

    def join_description_fragments(fragments)
      fragments.each_with_object(+"") do |fragment, description|
        if description.blank?
          description << fragment
        else
          description.replace(append_description_fragment(description, fragment))
        end
      end.squish
    end

    def append_description_fragment(description, fragment)
      day_match = description.match(/(?<head>.*(?:\A|\s))(?<tens>[1-3])\z/)
      continuation_match = fragment.match(/\A(?<ones>\d)\s+(?<month>#{MONTH_PATTERN})\s+(?<year>\d{2,4})(?<rest>(?:\s+.*)?)\z/i)

      if day_match.present? && continuation_match.present?
        combined_day = "#{day_match[:tens]}#{continuation_match[:ones]}".to_i
        if combined_day.between?(10, 31)
          return "#{day_match[:head]}#{combined_day} #{continuation_match[:month]} #{continuation_match[:year]}#{continuation_match[:rest]}".squish
        end
      end

      "#{description} #{fragment}".squish
    end

    def assigned_amount_candidates(block, assignments)
      return [] if assignments.blank?
      return assignments[:assigned_candidates] if assignments[:assigned_candidates].present?

      candidates = amount_candidates(block)
      assigned_amounts = assignments.slice(:debit, :credit, :balance, :amount).values.compact.map { |amount| amount.round(2) }
      candidates.select { |candidate| assigned_amounts.include?(candidate.fetch(:amount).round(2)) }
    end

    def clean_ocr_description(description)
      text = truncate_ocr_description_at_footer(description.to_s.squish)
      text = repair_trailing_split_ocr_word(text)
      text = text.split(/\s+/).filter_map do |token|
        cleaned = clean_ocr_description_token(token)
        next if cleaned.blank? || cleaned.match?(OCR_DESCRIPTION_NOISE_TOKEN_PATTERN)

        cleaned
      end.join(" ").squish
      text = strip_trailing_single_character_ocr_artifact(text)
      strip_trailing_attached_ocr_digit(text)
    end

    def truncate_ocr_description_at_footer(description)
      match = description.match(INLINE_STOP_BOUNDARY_PATTERN)
      return description if match.blank?

      description[0...match.begin(0)].to_s.rstrip
    end

    def clean_ocr_description_token(token)
      token.to_s.gsub(OCR_DESCRIPTION_EDGE_NOISE_PATTERN, "")
    end

    def repair_trailing_split_ocr_word(description)
      text = description.to_s.squish
      match = text.match(/(?<head>.*(?:\A|\s))(?<prefix>[A-Z]{2,4})\s+(?<tail>.+)\z/u)
      return text if match.blank?

      tail = match[:tail].to_s
      return text unless tail.match?(/[\[\]]/)

      suffix = trailing_split_ocr_suffix(match[:prefix], tail)
      return text if suffix.blank?

      "#{match[:head]}#{match[:prefix]}#{suffix}".squish
    end

    def trailing_split_ocr_suffix(prefix, tail)
      standalone_letters = tail.scan(/(?<![A-Za-z])([A-Za-z])(?![A-Za-z])/).flatten
      return standalone_letters.last.upcase if standalone_letters.one?

      return unless tail.match?(/[^\x00-\x7F]/)
      return if tail.scan(/[A-Za-z]+/).any? { |word| word.length > 5 }

      # Keep noisy multi-letter fallbacks to common short location abbreviations.
      tail.scan(/[A-Za-z]/).each do |letter|
        candidate = "#{prefix}#{letter}".upcase
        return letter.upcase if OCR_SPLIT_UPPERCASE_COMPLETIONS.include?(candidate)
      end

      nil
    end

    def strip_trailing_attached_ocr_digit(description)
      tokens = description.to_s.squish.split(/\s+/)
      return description if tokens.blank?

      match = tokens.last.to_s.match(/\A(?<word>\p{Alpha}{3,})(?<digit>\d)\z/u)
      return description if match.blank?
      return description if tokens[-2].to_s.match?(/\A(ref|reference|id|invoice|inv|account|acct|no|number)\z/i)

      tokens[-1] = match[:word]
      tokens.join(" ")
    end

    def strip_trailing_single_character_ocr_artifact(description)
      tokens = description.to_s.squish.split(/\s+/)
      return description if tokens.size < 2

      trailing = tokens.last.to_s
      return description unless trailing.match?(/\A\p{Alpha}\z/u)
      return description if trailing.match?(/\A[A-Z]\z/)

      tokens.pop
      tokens.join(" ")
    end

    def ocr_description_cleanup_header?(header_shape)
      scanned_debit_credit_balance_header?(header_shape) && !anz_business_extra_header?(header_shape)
    end

    def scrub_extracted_blank_tokens(value)
      value.to_s.gsub(EXTRACTED_BLANK_TOKEN_PATTERN, " ")
    end

    def truncate_inline_stop_boundary(line)
      raw = line.fetch(:raw).to_s
      match = raw.match(INLINE_STOP_BOUNDARY_PATTERN)
      return [ line, false ] if match.blank?

      original_raw = line.fetch(:original_raw).to_s
      original_match = original_raw.match(INLINE_STOP_BOUNDARY_PATTERN)
      if match.begin(0).zero?
        return [
          line.merge(
            raw: "",
            original_raw: original_match.present? && original_match.begin(0).zero? ? "" : original_raw
          ),
          true
        ]
      end

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
      text = value.to_s.squish
      number_match = text.match(/#{OCR_AMOUNT_NUMBER_SOURCE}/)
      return if number_match.blank?

      negative = text.include?("-") || text.match?(/\A\s*\(/)
      normalized = number_match[0].delete(",").sub(/(\.\d{2})\d+\z/, "\\1")
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

    def raise_parse_error(code)
      raise ParseError.new(UNREADABLE_PDF_MESSAGE, code: code)
    end

    def description_header?(normalized)
      normalized.match?(/\b(transaction description|transaction details|description|deseription|details)\b/)
    end

    def debit_header?(normalized)
      normalized.match?(/\b(debit|withdrawal|withdrawals|withdraw|debit amount)\b/)
    end

    def credit_header?(normalized)
      normalized.match?(/\b(credit|deposit|deposits|credit amount)\b/)
    end

    def balance_header?(normalized)
      normalized.match?(/\b(balance|running balance)\b/)
    end
  end
end
