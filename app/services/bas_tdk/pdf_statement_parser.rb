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
    BALANCE_SUFFIX_SOURCE = "(?:\\s*(?:CR|DR))?".freeze
    AMOUNT_PATTERN = /
      (?<![A-Za-z0-9])
      (?:
        \(\s*-?\s*[#{OCR_CURRENCY_MARKER_SOURCE}]?\s*#{AMOUNT_NUMBER_SOURCE}#{BALANCE_SUFFIX_SOURCE}\s*\) |
        -\s*[#{OCR_CURRENCY_MARKER_SOURCE}]?\s*#{AMOUNT_NUMBER_SOURCE}#{BALANCE_SUFFIX_SOURCE} |
        [#{OCR_CURRENCY_MARKER_SOURCE}]\s*-?\s*#{AMOUNT_NUMBER_SOURCE}#{BALANCE_SUFFIX_SOURCE} |
        #{AMOUNT_NUMBER_SOURCE}#{BALANCE_SUFFIX_SOURCE}
      )
      (?![A-Za-z0-9])
    /x
    OCR_AMOUNT_PATTERN = /
      (?<![A-Za-z0-9])
      (?:
        \(\s*-?\s*[#{OCR_CURRENCY_MARKER_SOURCE}]?\s*#{OCR_AMOUNT_NUMBER_SOURCE}#{BALANCE_SUFFIX_SOURCE}\s*\) |
        -\s*[#{OCR_CURRENCY_MARKER_SOURCE}]?\s*#{OCR_AMOUNT_NUMBER_SOURCE}#{BALANCE_SUFFIX_SOURCE} |
        [#{OCR_CURRENCY_MARKER_SOURCE}]\s*-?\s*#{OCR_AMOUNT_NUMBER_SOURCE}#{BALANCE_SUFFIX_SOURCE} |
        #{OCR_AMOUNT_NUMBER_SOURCE}#{BALANCE_SUFFIX_SOURCE}
      )
      (?![A-Za-z0-9])
    /x
    HEADER_BLOCK_SCAN_LIMIT = 5
    LOW_RECALL_CANDIDATE_MINIMUM = 30
    LOW_RECALL_RATIO = 0.70
    BALANCE_DELTA_TOLERANCE = BigDecimal("0.01")
    BALANCE_CONTINUITY_CHECK_MINIMUM = 10
    BALANCE_CONTINUITY_MISMATCH_MINIMUM = 3
    BALANCE_CONTINUITY_MISMATCH_RATIO = 0.05
    TRANSACTION_CANDIDATE_AMOUNT_LOOKAHEAD_LIMIT = 10
    RECONCILIATION_QUALITY_ROW_MINIMUM = 3
    OCR_DESCRIPTION_NOISE_TOKEN_PATTERN = /\A(?:-?[#{OCR_CURRENCY_MARKER_SOURCE}]+|[^\p{Alnum}]+)\z/u
    OCR_DESCRIPTION_EDGE_NOISE_PATTERN = /(?:\A[_~|"'\\\/\[\]\(\)\{\}.:;,\-]+|[_~|"'\\\/\[\]\(\)\{\}.:;,\-]+\z)/
    OCR_DESCRIPTION_TRAILING_NOISE_TOKEN_PATTERN = /\A(?:[_~|"'\\\/\[\]\(\)\{\}.:;,\-]+|\u{00C9}+|\u{00E9}+)\z/u
    OCR_SPLIT_UPPERCASE_COMPLETIONS = %w[VIC NSW QLD ACT TAS SA WA NT].freeze
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
        \bpage\s+\d+\s+of(?:\s+\d+)?\b |
        \b(
        closing\s+balance |
        opening\s+balance\s+-\s+total\s+debits |
        balance\s+carried\s+forward |
        convenience\s+at\s+your\s+fingertips |
        transaction\s+summary |
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
        opening\s+balance\s+total\s+debits |
        balance\s+carried\s+forward |
        convenience\s+at\s+your\s+fingertips |
        transaction\s+summary |
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
        transaction\s+summary |
        account\s+summary
      )\b
    /ix
    NON_TRANSACTION_DESCRIPTION_PATTERN = /
      \A\s*(
        statement\s+opening\s+balance |
        opening\s+balance |
        closing\s+balance |
        opening\s+balance\s+-\s+total\s+debits |
        totals?\s+at\s+end\s+of\s+(page|period) |
        transaction\s+summary |
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
      :metadata,
      keyword_init: true
    )
    HeaderShape = Struct.new(:line_number, :original_headers, :columns, :column_positions_reliable, keyword_init: true)
    TransactionBlock = Struct.new(:line_number, :lines, :header_shape, keyword_init: true)

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

      candidate_count = transaction_candidate_count(lines)
      opening_balance = extract_opening_balance(lines)
      closing_balance = extract_closing_balance(lines)
      blocks = transaction_blocks(lines, header_shape)
      rows = parsed_rows(blocks, header_shape, opening_balance: opening_balance)
      rows = reconcile_running_balances(rows)
      raise_parse_error(:no_transaction_table) if rows.blank?

      processed_headers = BASE_HEADERS.dup
      processed_headers << "Balance" if header_shape.columns.key?(:balance) || rows.any? { |row| row.fetch(:data)["Balance"].present? }
      rows.each { |row| processed_headers.each { |header| row.fetch(:data)[header] = "" unless row.fetch(:data).key?(header) } }

      ParsedStatement.new(
        sheet_name: SHEET_NAME,
        header_row_number: header_shape.line_number,
        original_headers: header_shape.original_headers,
        processed_headers: processed_headers,
        rows: rows,
        metadata: parse_metadata(
          rows: rows,
          candidate_count: candidate_count,
          opening_balance: opening_balance,
          closing_balance: closing_balance
        )
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
        candidate = header_candidate_at(lines, index, bank_context: bank_statement_context?(lines, index))
        next if candidate.blank?

        [ candidate.fetch(:score), line.fetch(:line_number), candidate.fetch(:shape) ]
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

    def header_candidate_at(lines, index, bank_context:)
      return unless header_start_line?(lines[index]&.fetch(:raw))

      max_count = [ HEADER_BLOCK_SCAN_LIMIT, lines.length - index ].min
      candidates = (1..max_count).filter_map do |count|
        block = lines[index, count]
        next if block.blank?
        next if block.any? { |line| line.fetch(:raw).match?(DATE_START_PATTERN) }

        combined = block.map { |line| line.fetch(:raw) }.join(" ")
        score = header_score(combined, bank_context: bank_context)
        next if score.zero?

        shape = header_shape_from_lines(block)
        next if shape.columns.blank?
        next unless transaction_table_header_shape?(shape)

        { score: score + count, shape: shape, line_count: count }
      end

      candidates.max_by { |candidate| [ candidate.fetch(:score), candidate.fetch(:line_count) ] }
    end

    def header_start_line?(raw)
      return false if raw.to_s.match?(DATE_START_PATTERN)

      normalized = normalize(raw)
      return true if normalized.match?(/\Adate(?:\s|\z)/)

      normalized.match?(/\A(?:transaction|effective)\s+date\b/) &&
        description_header?(normalized) &&
        (debit_header?(normalized) || credit_header?(normalized) || balance_header?(normalized))
    end

    def header_shape(line)
      header_shape_from_lines([ line ])
    end

    def header_shape_from_lines(lines)
      columns = {}
      column_patterns.each do |key, pattern|
        columns[key] = lines.filter_map { |line| column(key, line.fetch(:raw), pattern) }.first
      end
      columns.compact!

      HeaderShape.new(
        line_number: lines.first.fetch(:line_number),
        original_headers: original_headers(columns),
        columns: columns,
        column_positions_reliable: reliable_header_column_positions?(columns)
      )
    end

    def column_patterns
      {
        date: /\b(transaction\s+date|effective\s+date|date)\b/i,
        description: /\b(transaction\s+description|transaction\s+details|description|deseription|details|narration|particulars|transaction(?!\s+date))\b/i,
        debit: /\b(debit\s+amount|debits?(?:\s+\(\$\))?|withdrawals?(?:\s+\(\$\))?|money\s+out(?:\s+\(\$\))?|payments?(?:\s+\(\$\))?|paid\s+out)\b/i,
        credit: /\b(credit\s+amount|credits?(?:\s+\(\$\))?|deposits?(?:\s+\(\$\))?|money\s+in(?:\s+\(\$\))?|receipts?(?:\s+\(\$\))?|paid\s+in)\b/i,
        balance: /\b(running\s+balance(?:\s+\(\$\))?|balance(?:\s+\(\$\))?)\b/i
      }
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

    def reliable_header_column_positions?(columns)
      starts = [ :date, :description, :debit, :credit, :balance ].filter_map { |key| columns.dig(key, :start)&.to_i }
      return false if starts.size < 4

      starts == starts.sort && starts.uniq.size == starts.size
    end

    def transaction_table_header_shape?(shape)
      shape.columns.key?(:date) &&
        shape.columns.key?(:balance) &&
        (shape.columns.key?(:debit) || shape.columns.key?(:credit))
    end

    def transaction_blocks(lines, header_shape)
      blocks = []
      current = nil
      in_table = false
      active_header_shape = nil

      index = 0
      while index < lines.length
        line = lines[index]
        raw = line.fetch(:raw)

        header_candidate = header_candidate_at(lines, index, bank_context: true)
        if header_candidate.present?
          blocks << current if current.present?
          current = nil
          active_header_shape = header_candidate.fetch(:shape)
          in_table = true
          index += header_candidate.fetch(:line_count)
          next
        end

        unless in_table
          index += 1
          next
        end

        line, stop_after_line = truncate_inline_stop_boundary(line)
        raw = line.fetch(:raw)
        squished = raw.squish

        if squished.blank?
          if stop_after_line
            blocks << current if current.present?
            current = nil
            active_header_shape = nil
            in_table = false
          end
          index += 1
          next
        end

        if table_stop_line?(squished)
          blocks << current if current.present?
          current = nil
          active_header_shape = nil
          in_table = false
          index += 1
          next
        end

        if skip_line?(squished)
          index += 1
          next
        end

        current_header_shape = active_header_shape || header_shape

        if raw.match?(DATE_START_PATTERN)
          if current.present? && date_starting_continuation_line?(raw, current.header_shape || current_header_shape)
            current.lines << line
          elsif non_transaction_dated_line?(raw)
            blocks << current if current.present?
            current = nil
          else
            blocks << current if current.present?
            current = TransactionBlock.new(line_number: line.fetch(:line_number), lines: [ line ], header_shape: current_header_shape)
          end
        elsif current.present? && continuation_line?(raw, current.header_shape || current_header_shape)
          current.lines << line
        end

        if stop_after_line
          blocks << current if current.present?
          current = nil
          active_header_shape = nil
          in_table = false
        end

        index += 1
      end

      blocks << current if current.present?
      blocks
    end

    def transaction_candidate_count(lines)
      count = 0
      in_table = false
      index = 0

      while index < lines.length
        header_candidate = header_candidate_at(lines, index, bank_context: true)
        if header_candidate.present?
          in_table = true
          index += header_candidate.fetch(:line_count)
          next
        end

        unless in_table
          index += 1
          next
        end

        line, stop_after_line = truncate_inline_stop_boundary(lines[index])
        raw = line.fetch(:raw)
        squished = raw.squish

        if squished.blank?
          in_table = false if stop_after_line
          index += 1
          next
        end

        if table_stop_line?(squished)
          in_table = false
          index += 1
          next
        end

        if !skip_line?(squished) && raw.match?(DATE_START_PATTERN) && !non_transaction_dated_line?(raw) && transaction_candidate_amount_nearby?(lines, index)
          count += 1
        end

        in_table = false if stop_after_line
        index += 1
      end

      count
    end

    def transaction_candidate_amount_nearby?(lines, index)
      lines[index, TRANSACTION_CANDIDATE_AMOUNT_LOOKAHEAD_LIMIT].to_a.each_with_index do |source_line, offset|
        line, stop_after_line = truncate_inline_stop_boundary(source_line)
        raw = line.fetch(:raw)
        break if offset.positive? && raw.match?(DATE_START_PATTERN)
        break if header_candidate_at(lines, index + offset, bank_context: true).present?

        squished = raw.squish
        break if offset.positive? && table_stop_line?(squished)
        next if squished.blank? || skip_line?(squished)

        return true if raw.match?(AMOUNT_PATTERN) || raw.match?(OCR_AMOUNT_PATTERN)
        break if stop_after_line
      end

      false
    end

    def extract_opening_balance(lines)
      lines.each do |line|
        raw = line.fetch(:raw)
        next unless normalize(raw).include?("opening balance")

        amounts = raw.scan(OCR_AMOUNT_PATTERN).filter_map { |amount| parse_amount(amount) }
        return amounts.last if amounts.any?
      end

      nil
    end

    def extract_closing_balance(lines)
      lines.reverse_each do |line|
        raw = line.fetch(:raw)
        next unless normalize(raw).include?("closing balance")

        amounts = raw.scan(OCR_AMOUNT_PATTERN).filter_map { |amount| parse_amount(amount) }
        return amounts.last if amounts.any?
      end

      nil
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

    def parsed_rows(blocks, header_shape, opening_balance: nil)
      previous_balance = opening_balance
      rows = []

      blocks.each do |block|
        row = parsed_row(block, block.header_shape || header_shape, rows.length + 1, previous_balance: previous_balance)
        next if row.blank?

        previous_balance = parse_amount(row.fetch(:data)["Balance"]) if row.fetch(:data)["Balance"].present?
        rows << row
      end

      rows
    end

    def reconcile_running_balances(rows)
      previous_balance = nil

      rows.each do |row|
        data = row.fetch(:data)
        amount = parse_amount(data["Amount"])
        balance = parse_amount(data["Balance"])

        if amount.present? && balance.present? && previous_balance.present?
          delta = balance - previous_balance
          data["Amount"] = serialize_amount(delta) if amounts_equal?(amount.abs, delta.abs) && !amounts_equal?(amount, delta)
        end

        previous_balance = balance if balance.present?
      end

      rows.each_with_index do |row, index|
        row[:position] = index + 1
      end
    end

    def parse_metadata(rows:, candidate_count:, opening_balance:, closing_balance:)
      row_count = rows.size
      balance_count = rows.count { |row| row.fetch(:data)["Balance"].present? }
      description_count = rows.count { |row| row.fetch(:data)["Description"].present? }
      amount_count = rows.count { |row| row.fetch(:data)["Amount"].present? }
      low_recall = candidate_count >= LOW_RECALL_CANDIDATE_MINIMUM && row_count < (candidate_count * LOW_RECALL_RATIO)
      continuity = balance_continuity_metadata(rows, opening_balance: opening_balance)
      reconciliation = statement_reconciliation_metadata(rows, opening_balance: opening_balance, closing_balance: closing_balance)
      poor_balance_continuity = poor_balance_continuity?(continuity)
      reconciliation_mismatch = statement_reconciliation_quality_failure?(rows: rows, reconciliation: reconciliation)
      quality = if low_recall
        "low_recall"
      elsif poor_balance_continuity
        "poor_balance_continuity"
      elsif reconciliation_mismatch
        "statement_reconciliation_mismatch"
      else
        "good"
      end

      {
        "row_count" => row_count,
        "candidate_transaction_count" => candidate_count,
        "quality" => quality,
        "quality_score" => parse_quality_score(
          row_count: row_count,
          candidate_count: candidate_count,
          balance_count: balance_count,
          amount_count: amount_count,
          continuity: continuity,
          reconciliation: reconciliation,
          low_recall: low_recall,
          poor_balance_continuity: poor_balance_continuity,
          reconciliation_mismatch: reconciliation_mismatch
        ),
        "balance_coverage" => coverage_ratio(balance_count, row_count),
        "amount_coverage" => coverage_ratio(amount_count, row_count),
        "description_coverage" => coverage_ratio(description_count, row_count),
        "footer_header_contamination_count" => footer_header_contamination_count(rows)
      }.merge(continuity).merge(reconciliation)
    end

    def balance_continuity_metadata(rows, opening_balance:)
      previous_balance = opening_balance
      check_count = 0
      mismatch_count = 0

      rows.each do |row|
        data = row.fetch(:data)
        amount = parse_amount(data["Amount"])
        balance = parse_amount(data["Balance"])

        if previous_balance.present? && amount.present? && balance.present?
          check_count += 1
          mismatch_count += 1 unless amounts_equal?(balance - previous_balance, amount)
        end

        previous_balance = balance if balance.present?
      end

      {
        "balance_continuity_check_count" => check_count,
        "balance_continuity_mismatch_count" => mismatch_count,
        "balance_continuity_coverage" => coverage_ratio(check_count, rows.size),
        "balance_continuity_mismatch_ratio" => check_count.positive? ? (mismatch_count.to_f / check_count).round(4) : 0.0
      }
    end

    def poor_balance_continuity?(metadata)
      metadata.fetch("balance_continuity_check_count").to_i >= BALANCE_CONTINUITY_CHECK_MINIMUM &&
        metadata.fetch("balance_continuity_mismatch_count").to_i >= BALANCE_CONTINUITY_MISMATCH_MINIMUM &&
      metadata.fetch("balance_continuity_mismatch_ratio").to_f > BALANCE_CONTINUITY_MISMATCH_RATIO
    end

    def statement_reconciliation_metadata(rows, opening_balance:, closing_balance:)
      amount_sum = rows.sum(BigDecimal("0")) do |row|
        parse_amount(row.fetch(:data)["Amount"]) || BigDecimal("0")
      end

      metadata = {
        "opening_balance_present" => opening_balance.present?,
        "closing_balance_present" => closing_balance.present?,
        "statement_reconciliation_amount_sum" => serialize_amount(amount_sum),
        "statement_reconciliation_expected_delta" => nil,
        "statement_reconciliation_delta_mismatch" => nil
      }

      if opening_balance.blank? || closing_balance.blank?
        return metadata.merge("statement_reconciliation_status" => "not_available")
      end

      expected_delta = closing_balance - opening_balance
      delta_mismatch = amount_sum - expected_delta
      metadata.merge(
        "statement_reconciliation_status" => amounts_equal?(amount_sum, expected_delta) ? "matched" : "mismatch",
        "statement_reconciliation_expected_delta" => serialize_amount(expected_delta),
        "statement_reconciliation_delta_mismatch" => serialize_amount(delta_mismatch)
      )
    end

    def statement_reconciliation_quality_failure?(rows:, reconciliation:)
      rows.size >= RECONCILIATION_QUALITY_ROW_MINIMUM &&
        reconciliation.fetch("statement_reconciliation_status") == "mismatch"
    end

    def footer_header_contamination_count(rows)
      rows.count do |row|
        description = row.fetch(:data)["Description"].to_s
        normalized = normalize(description)

        description.match?(NON_TRANSACTION_DESCRIPTION_PATTERN) ||
          normalized.match?(TABLE_STOP_NORMALIZED_PATTERN) ||
          header_score(description).positive?
      end
    end

    def parse_quality_score(
      row_count:,
      candidate_count:,
      balance_count:,
      amount_count:,
      continuity:,
      reconciliation:,
      low_recall:,
      poor_balance_continuity:,
      reconciliation_mismatch:
    )
      recall = candidate_count.positive? ? row_count.to_f / candidate_count : 1.0
      balance_coverage = coverage_ratio(balance_count, row_count)
      amount_coverage = coverage_ratio(amount_count, row_count)
      continuity_coverage = continuity.fetch("balance_continuity_coverage").to_f
      mismatch_count = continuity.fetch("balance_continuity_mismatch_count").to_i
      mismatch_ratio = continuity.fetch("balance_continuity_mismatch_ratio").to_f
      reconciliation_bonus = reconciliation.fetch("statement_reconciliation_status") == "matched" ? 50 : 0
      penalty = (mismatch_count * 20) + (mismatch_ratio * 300)
      penalty += 300 if low_recall
      penalty += 500 if poor_balance_continuity
      penalty += 400 if reconciliation_mismatch

      (
        (row_count * 10) +
        (recall * 100) +
        (balance_coverage * 20) +
        (amount_coverage * 20) +
        (continuity_coverage * 20) -
        penalty +
        reconciliation_bonus
      ).round(2)
    end

    def coverage_ratio(count, total)
      return 1.0 if total.zero?

      (count.to_f / total).round(4)
    end

    def parsed_row(block, header_shape, position, previous_balance: nil)
      first_line = block.lines.first.fetch(:raw)
      date_match = first_line.match(DATE_START_PATTERN)
      return if date_match.blank?

      date = parse_date(date_match[:date])
      return if date.blank?

      assignments = assign_amounts(block, header_shape, previous_balance: previous_balance)
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

    def assign_amounts(block, header_shape, previous_balance: nil)
      candidates = amount_candidates(block, amount_pattern: amount_pattern_for_header(header_shape))
      return {} if candidates.blank?

      return assign_anz_business_extra_amounts(block, header_shape, candidates) if anz_business_extra_header?(header_shape)

      if scanned_debit_credit_balance_header?(header_shape)
        structured_assignments = assign_structured_debit_credit_balance_amounts(block, header_shape, candidates, previous_balance: previous_balance)
        return structured_assignments if transaction_amount(structured_assignments).present?

        scanned_assignments = assign_scanned_debit_credit_balance_amounts(block, header_shape, candidates)
        return scanned_assignments if scanned_assignments.present?
        return {}
      end

      assignments = assign_amounts_by_position(candidates, header_shape)
      assignments = assign_amounts_by_fallback(candidates, header_shape) if transaction_amount(assignments).blank?
      assignments = apply_balance_delta_to_assignments(assignments, candidates, previous_balance: previous_balance)
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
      amount_column = classify_amount_column_from_debit_credit_layout(block, transaction_candidate, balance_candidate, layout: header_shape) ||
        anz_blank_marker_column(block, transaction_candidate, balance_candidate) ||
        strict_amount_column(transaction_candidate, header_shape, [ :debit, :credit ])
      return assignments if amount_column.blank?

      assignments[amount_column] = transaction_candidate.fetch(:amount)
      assignments[:assigned_candidates] << transaction_candidate
      assignments
    end

    def assign_structured_debit_credit_balance_amounts(block, header_shape, candidates, previous_balance: nil)
      return {} unless debit_credit_column_layout?(header_shape)
      return {} unless header_shape.columns.key?(:balance)
      return {} if candidates.size < 2

      balance_candidate = candidates.last
      assignments = {
        balance: balance_candidate.fetch(:amount),
        assigned_candidates: [ balance_candidate ]
      }

      transaction_candidates = candidates[0...-1]
      transaction_candidates.reverse_each do |candidate|
        amount_column = classify_amount_column_from_debit_credit_layout(block, candidate, balance_candidate, layout: header_shape)
        next unless amount_column.in?([ :debit, :credit ])

        assignments[amount_column] = candidate.fetch(:amount)
        assignments[:assigned_candidates] << candidate
        break
      end

      assignments = apply_balance_delta_to_assignments(assignments, candidates, previous_balance: previous_balance)
      return {} if transaction_amount(assignments).blank?

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
      return {} unless header_shape.column_positions_reliable

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
        span_key = amount_column_from_header_spans(candidate, header_shape)
        key, distance = if amount_columns.any? { |column_key, _start| column_key == span_key }
          [ span_key, 0 ]
        else
          closest_amount_column(candidate, amount_columns)
        end
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

      debit_column_label?(debit_label) &&
        credit_column_label?(credit_label) &&
        balance_label.match?(/\b(running balance|balance)\b/)
    end

    def assign_scanned_debit_credit_balance_amounts(block, header_shape, candidates)
      return {} unless header_shape.columns.key?(:balance)
      return {} if candidates.size < 2

      balance_candidate = candidates.last
      transaction_candidate = candidates[0...-1].last
      direction = classify_amount_column_from_debit_credit_layout(
        block,
        transaction_candidate,
        balance_candidate,
        layout: header_shape,
        allow_column_position: false
      )
      direction ||= reliable_scanned_amount_column(transaction_candidate, header_shape)
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

      balance_start = header_shape.columns.dig(:balance, :start)
      return if balance_start.present? && candidate.fetch(:start) >= balance_start.to_i

      first_amount_start = amount_columns.map(&:second).min
      return if first_amount_start.present? && candidate.fetch(:start) < first_amount_start - 4

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

    def classify_amount_column_from_debit_credit_layout(block, transaction_candidate, balance_candidate, layout:, allow_column_position: true)
      return unless debit_credit_column_layout?(layout)

      if allow_column_position
        span_column = amount_column_from_header_spans(transaction_candidate, layout)
        return span_column if span_column.in?([ :debit, :credit ])
      end

      blank_marker_column = amount_column_from_candidate_original_line(block, transaction_candidate, balance_candidate)
      return blank_marker_column if blank_marker_column.present?

      currency_marker_column = amount_column_from_currency_marker_pattern(block, transaction_candidate, balance_candidate)
      return currency_marker_column if currency_marker_column.present?

      nil
    end

    def debit_credit_column_layout?(header_shape)
      return false if header_shape.blank?

      debit_column_label?(normalize(header_shape.columns.dig(:debit, :label))) &&
        credit_column_label?(normalize(header_shape.columns.dig(:credit, :label))) &&
        header_shape.columns.key?(:balance)
    end

    def amount_column_from_candidate_original_line(block, transaction_candidate, balance_candidate)
      return if balance_candidate.blank?

      line = block.lines[transaction_candidate.fetch(:line_index)]
      return if line.blank?

      blank_marker_amount_column(line.fetch(:original_raw).to_s, transaction_candidate, balance_candidate)
    end

    def blank_marker_amount_column(text, transaction_candidate, balance_candidate)
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

    def amount_column_from_currency_marker_pattern(block, transaction_candidate, balance_candidate)
      return if transaction_candidate.blank? || balance_candidate.blank?

      line = block.lines[transaction_candidate.fetch(:line_index)]
      return if line.blank?

      raw = line.fetch(:original_raw).to_s
      transaction_raw = transaction_candidate.fetch(:raw).to_s
      return :credit if transaction_raw.match?(/\A\s*[#{OCR_CURRENCY_MARKER_SOURCE}]/) && balance_candidate.fetch(:raw).match?(/\b(?:CR|DR)\s*\z/i)

      return unless balance_candidate.fetch(:line_index) == transaction_candidate.fetch(:line_index)

      between = raw[transaction_candidate.fetch(:end)...balance_candidate.fetch(:start)].to_s
      return :debit if between.match?(/(?:\A|\s)[#{OCR_CURRENCY_MARKER_SOURCE}](?:\s|\z)/)

      nil
    end

    def apply_balance_delta_to_assignments(assignments, candidates, previous_balance:)
      return assignments if previous_balance.blank?
      return assignments unless assignments[:balance].present?

      delta = assignments.fetch(:balance) - previous_balance
      return assignments if delta.zero?

      current_amount = transaction_amount(assignments)
      if current_amount.present? && amounts_equal?(current_amount.abs, delta.abs)
        return assignments if amounts_equal?(current_amount, delta)

        return reassign_transaction_amount(assignments, current_amount.abs, delta)
      end

      transaction_candidates = candidates[0...-1].to_a
      matching_candidate = transaction_candidates.reverse.find { |candidate| amounts_equal?(candidate.fetch(:amount).abs, delta.abs) }
      return assignments if matching_candidate.blank?

      key = delta.positive? ? :credit : :debit
      assignments = assignments.except(:debit, :credit, :amount).merge(key => matching_candidate.fetch(:amount).abs)
      assignments[:assigned_candidates] = [ *assignments[:assigned_candidates], matching_candidate ].compact.uniq
      assignments
    end

    def reassign_transaction_amount(assignments, absolute_amount, delta)
      key = delta.positive? ? :credit : :debit
      assignments = assignments.except(:debit, :credit, :amount).merge(key => absolute_amount)
      assignments
    end

    def amounts_equal?(left, right)
      (BigDecimal(left.to_s) - BigDecimal(right.to_s)).abs <= BALANCE_DELTA_TOLERANCE
    end

    def amount_column_from_header_spans(candidate, header_shape)
      return unless debit_credit_column_layout?(header_shape)
      return unless header_shape.column_positions_reliable
      return unless amount_column_spacing_reliable?(candidate)

      debit_start = header_shape.columns.dig(:debit, :start).to_i
      credit_start = header_shape.columns.dig(:credit, :start).to_i
      balance_start = header_shape.columns.dig(:balance, :start).to_i
      return unless debit_start < credit_start && credit_start < balance_start

      candidate_start = candidate.fetch(:start)
      candidate_end = candidate.fetch(:end)
      return if candidate_start < minimum_amount_area_start(header_shape)

      if candidate_start < credit_start
        return :debit if candidate_end <= credit_start
        return :debit if basic_debit_credit_label_pair?(header_shape) && candidate_end <= balance_start

        return
      end

      return :credit if candidate_start >= credit_start && candidate_end <= balance_start
      return :balance if candidate_start >= balance_start || candidate_end > balance_start

      nil
    end

    def minimum_amount_area_start(header_shape)
      debit_start = header_shape.columns.dig(:debit, :start).to_i
      description_start = header_shape.columns.dig(:description, :start)
      starts = [ [ debit_start - 16, 0 ].max ]
      starts << description_start.to_i + 12 if description_start.present?

      starts.max
    end

    def basic_debit_credit_label_pair?(header_shape)
      debit_label = normalize(header_shape.columns.dig(:debit, :label))
      credit_label = normalize(header_shape.columns.dig(:credit, :label))

      debit_label.match?(/\bdebits?\b/) && credit_label.match?(/\bcredits?\b/)
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
        strip_balance_suffixes!(raw, index, assigned_candidates, assignments[:balance])
        assigned_candidates.select { |candidate| candidate.fetch(:line_index) == index }.each do |candidate|
          raw[candidate.fetch(:start)...candidate.fetch(:end)] = " " * (candidate.fetch(:end) - candidate.fetch(:start))
        end
        raw = strip_table_column_artifacts(raw, header_shape, start_index)
        raw[start_index..].to_s.squish
      end.reject(&:blank?)

      description = join_description_fragments(fragments)

      ocr_description_cleanup?(header_shape, block) ? clean_ocr_description(description) : description
    end

    def strip_balance_suffixes!(raw, line_index, assigned_candidates, balance_amount)
      return if balance_amount.blank?

      assigned_candidates.each do |candidate|
        next unless candidate.fetch(:line_index) == line_index
        next unless candidate.fetch(:amount).round(2) == balance_amount.round(2)

        match = raw[candidate.fetch(:end)..].to_s.match(/\A\s*(?:CR|DR)\b/i)
        next if match.blank?

        raw[candidate.fetch(:end)...candidate.fetch(:end) + match.end(0)] = " " * match.end(0)
      end
    end

    def strip_table_column_artifacts(raw, header_shape, start_index)
      return raw unless debit_credit_column_layout?(header_shape)

      amount_area_start = [ :debit, :credit, :balance ].filter_map { |key| header_shape.columns.dig(key, :start) }.map(&:to_i).min
      return raw if amount_area_start.blank?

      cleanup_start = [ amount_area_start - 2, start_index ].max
      prefix = raw[0...cleanup_start].to_s
      suffix = raw[cleanup_start..].to_s
      suffix = suffix.gsub(EXTRACTED_BLANK_TOKEN_PATTERN, " ")
      suffix = suffix.gsub(/(?<![A-Za-z0-9])[#{OCR_CURRENCY_MARKER_SOURCE}](?![A-Za-z0-9])/, " ")

      prefix + suffix
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
      text = clean_ocr_description_tokens(text)
      text = strip_trailing_single_character_ocr_artifact(text)
      text = strip_trailing_attached_ocr_digit(text)
      text = truncate_ocr_description_at_footer(text)
      text = strip_trailing_single_character_ocr_artifact(text)
      text = strip_trailing_attached_ocr_digit(text)
      strip_trailing_ocr_noise(text)
    end

    def clean_ocr_description_tokens(description)
      description.to_s.split(/\s+/).filter_map do |token|
        cleaned = clean_ocr_description_token(token)
        next if cleaned.blank? || cleaned.match?(OCR_DESCRIPTION_NOISE_TOKEN_PATTERN)

        cleaned
      end.join(" ").squish
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
      match = text.match(/(?<head>.*(?:\A|\s))(?<prefix>[A-Z]{1,3})\s+(?<tail>.+)\z/u)
      return text if match.blank?

      tail = match[:tail].to_s
      return text unless split_ocr_tail_noise?(tail)

      suffix = trailing_split_ocr_suffix(match[:prefix], tail)
      return text if suffix.blank?

      "#{match[:head]}#{match[:prefix]}#{suffix}".squish
    end

    def split_ocr_tail_noise?(tail)
      tail.match?(/[_~|"'\\\/\[\]\(\)\{\}.:;,\-]/) || tail.match?(/[^\x00-\x7F]/)
    end

    def trailing_split_ocr_suffix(prefix, tail)
      return unless split_ocr_tail_noise?(tail)

      standalone_letters = tail.scan(/(?<![A-Za-z])([A-Za-z])(?![A-Za-z])/).flatten
      letter_candidates = standalone_letters.dup

      if tail.match?(/[^\x00-\x7F]/) || letter_candidates.blank?
        return if tail.scan(/[A-Za-z]+/).any? { |word| word.length > 5 }

        # Keep noisy multi-letter fallbacks to common short location abbreviations.
        letter_candidates.concat(tail.scan(/[A-Za-z]/))
      end

      letter_candidates.each do |letter|
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

    def strip_trailing_ocr_noise(description)
      tokens = description.to_s.squish.split(/\s+/)
      return "" if tokens.blank?

      while tokens.any?
        trailing = tokens.last.to_s
        cleaned = clean_ocr_description_token(trailing)

        if cleaned.blank? || cleaned.match?(OCR_DESCRIPTION_NOISE_TOKEN_PATTERN) || cleaned.match?(OCR_DESCRIPTION_TRAILING_NOISE_TOKEN_PATTERN)
          tokens.pop
        else
          tokens[-1] = cleaned
          break
        end
      end

      tokens.join(" ")
    end

    def ocr_description_cleanup?(header_shape, block)
      scanned_debit_credit_balance_header?(header_shape) &&
        !anz_business_extra_header?(header_shape) &&
        !balance_suffix_block?(block)
    end

    def balance_suffix_block?(block)
      block.lines.any? { |line| line.fetch(:raw).match?(/#{AMOUNT_NUMBER_SOURCE}\s*(?:CR|DR)\b/i) }
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
      squished = line.to_s.squish
      normalized = normalize(squished)

      normalized.match?(SKIP_LINE_NORMALIZED_PATTERN) ||
        normalized.match?(/\Aaccount\s+number\b/) ||
        squished.match?(/\Astatement\s+\d+(?:\s*\(|\s+page\b|\z)/i) ||
        squished.match?(/\A(?:\*#\*)+\z/) ||
        technical_statement_reference_line?(squished)
    end

    def technical_statement_reference_line?(line)
      text = line.to_s.squish
      return false if text.blank?
      return false if text.match?(DATE_START_PATTERN)
      return true if text.match?(/\A[A-Z]?\d{2}\.\d{2}\.\d{2,}\b/i)
      return true if text.match?(/\A\d{2,}(?:\.\d+){2,}\s+[A-Z0-9][A-Z0-9.*#-]*(?:\s+[A-Z0-9][A-Z0-9.*#-]*)*\z/i)

      tokens = text.split(/\s+/)
      return false if tokens.size < 3
      return false if tokens.any? { |token| token.match?(/[a-z]/) }

      code_tokens = tokens.count { |token| token.match?(/\A[A-Z0-9.*#-]+\z/) && token.match?(/\d/) }
      code_tokens >= 2 && code_tokens >= (tokens.size * 0.75)
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

      suffix = text.match(/(?<suffix>CR|DR)\s*\)?\z/i)&.[](:suffix).to_s.upcase
      negative = if suffix == "DR"
        true
      elsif suffix == "CR"
        false
      else
        text.include?("-") || text.match?(/\A\s*\(/)
      end
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
      normalized.match?(/\b(transaction description|transaction details|description|deseription|details|narration|particulars|transaction)\b/)
    end

    def debit_header?(normalized)
      debit_column_label?(normalized)
    end

    def credit_header?(normalized)
      credit_column_label?(normalized)
    end

    def debit_column_label?(normalized)
      normalized.to_s.match?(/\b(debit amount|debit|debits|withdrawal|withdrawals|withdraw|money out|payment|payments|paid out)\b/)
    end

    def credit_column_label?(normalized)
      normalized.to_s.match?(/\b(credit amount|credit|credits|deposit|deposits|money in|receipt|receipts|paid in)\b/)
    end

    def balance_header?(normalized)
      normalized.match?(/\b(balance|running balance)\b/)
    end
  end
end
