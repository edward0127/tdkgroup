module BasTdk
  class StatementColumnDetector
    PROFILE_ROW_LIMIT = 100
    START_ROW_SCAN_LIMIT = 20
    MAX_ROW_SCAN_LIMIT = 10_000
    MAX_COLUMN_SCAN_LIMIT = 128
    POPULATED_COLUMN_ROW_SCAN_LIMIT = 256
    PREVIEW_ROW_LIMIT = 8
    SAMPLE_VALUE_LIMIT = 5
    MIN_AUTO_SAMPLE_ROWS = 3
    DATE_SCORE_MINIMUM = 0.80
    DESCRIPTION_SCORE_MINIMUM = 0.72
    MONEY_PARSE_RATE_MINIMUM = 0.90
    MONEY_COVERAGE_MINIMUM = 0.08
    DENSE_MONEY_COVERAGE_MINIMUM = 0.65
    RECONCILIATION_MINIMUM = 0.80
    RECONCILIATION_MINIMUM_COMPARISONS = 3
    WINNER_MARGIN_MINIMUM = 0.08
    AMOUNT_TOLERANCE = BigDecimal("0.02")
    AUTO_SINGLETON_ROLES = %w[date description amount debit credit balance details category gst].freeze

    Result = Struct.new(
      :decision,
      :header_row_number,
      :data_start_row,
      :mapping,
      :confidence,
      :reason_codes,
      :columns,
      :preview_rows,
      :max_row,
      :max_column,
      keyword_init: true
    ) do
      def auto?
        decision == :auto
      end

      def needs_mapping?
        decision == :needs_mapping
      end

      def metadata
        {
          "decision" => decision.to_s,
          "header_row_number" => header_row_number,
          "data_start_row" => data_start_row,
          "max_row" => max_row,
          "max_column" => max_column,
          "mapping" => mapping,
          "suggested_mapping" => mapping,
          "confidence" => confidence,
          "reason_codes" => reason_codes,
          "columns" => columns,
          "preview_rows" => preview_rows
        }
      end
    end

    Profile = Struct.new(
      :index,
      :values,
      :non_blank_count,
      :date_score,
      :money_parse_rate,
      :money_coverage,
      :description_score,
      :identifier_like,
      keyword_init: true
    )

    Candidate = Struct.new(
      :data_start_row,
      :row_numbers,
      :profiles,
      :mapping,
      :score,
      :runner_up_score,
      :reason_codes,
      keyword_init: true
    )

    MoneySolution = Struct.new(:mapping, :score, :reconciliation, :coverage, :kind, keyword_init: true)

    def initialize(sheet:)
      @sheet = sheet
    end

    def call
      return empty_result if max_row.zero? || column_indices.size < 3

      best = candidate_start_rows.lazy.filter_map { |row_number| candidate_for(row_number) }.first
      return review_result_without_candidate if best.blank?

      confident = confident_candidate?(best)
      result_for(best, decision: confident ? :auto : :needs_mapping)
    end

    private

    attr_reader :sheet

    def max_row
      @max_row ||= [ [ sheet.last_row.to_i, 0 ].max, MAX_ROW_SCAN_LIMIT ].min
    end

    def max_column
      @max_column ||= column_indices.last.to_i + (column_indices.any? ? 1 : 0)
    end

    def scan_column_count
      @scan_column_count ||= [ [ sheet.last_column.to_i, 0 ].max, MAX_COLUMN_SCAN_LIMIT ].min
    end

    def column_indices
      @column_indices ||= begin
        if max_row.zero? || scan_column_count.zero?
          []
        else
          populated = {}
          row_limit = [ max_row, POPULATED_COLUMN_ROW_SCAN_LIMIT ].min
          (1..row_limit).each do |row_number|
            (0...scan_column_count).each do |index|
              populated[index] = true if cell_value(row_number, index).present?
            end
            break if populated.size == scan_column_count
          end
          populated.keys.sort
        end
      end
    end

    def candidate_start_rows
      rows = (1..[ max_row, START_ROW_SCAN_LIMIT ].min).select { |row_number| meaningful_row?(row_number) }
      rows.presence || [ 1 ]
    end

    def candidate_for(data_start_row)
      return unless transaction_shaped_row?(data_start_row)

      row_numbers = meaningful_row_numbers_from(data_start_row, limit: PROFILE_ROW_LIMIT)
      return if row_numbers.blank?

      profiles = column_indices.map { |index| profile_column(index, row_numbers) }
      date_candidates = ranked_date_candidates(profiles)
      description_candidates = ranked_description_candidates(profiles)
      return if date_candidates.blank? || description_candidates.blank?

      solutions = []
      date_candidates.first(2).each do |date_profile|
        description_candidates.first(3).each do |description_profile|
          next if date_profile.index == description_profile.index

          money_solutions(profiles, row_numbers, excluded_indices: [ date_profile.index, description_profile.index ]).each do |money|
            mapping = money.mapping.merge(
              date_profile.index.to_s => "date",
              description_profile.index.to_s => "description"
            )
            type_score = (date_profile.date_score + description_profile.description_score) / 2.0
            sample_reliability = 0.70 + ([ row_numbers.size / 10.0, 1.0 ].min * 0.30)
            total_score = ((type_score * 0.45) + (money.score * 0.55)) * sample_reliability
            solutions << [ total_score, mapping, money, date_profile, description_profile ]
          end
        end
      end
      return if solutions.blank?

      ranked = solutions.sort_by { |solution| -solution.first }
      best_score, detected_mapping, money, date_profile, description_profile = ranked.first
      runner_up = ranked.second&.first.to_f
      rewound_start_row = rewound_data_start_row(detected_mapping, data_start_row)
      mapping = suggested_mapping(detected_mapping, profiles, rewound_start_row)
      final_start_row = rewound_data_start_row(mapping, rewound_start_row)
      if final_start_row != rewound_start_row
        rewound_start_row = final_start_row
        mapping = suggested_mapping(detected_mapping, profiles, rewound_start_row)
      end
      reasons = []
      reasons << "short_sample" if row_numbers.size < MIN_AUTO_SAMPLE_ROWS
      reasons << "date_low_confidence" if date_profile.date_score < DATE_SCORE_MINIMUM
      reasons << "description_low_confidence" if description_profile.description_score < DESCRIPTION_SCORE_MINIMUM
      reasons << "mapping_ambiguous" if best_score - runner_up < WINNER_MARGIN_MINIMUM && materially_different?(detected_mapping, ranked.second&.[](1))
      reasons << "money_columns_ambiguous" if money.kind == :ambiguous
      if serial_only_date_profile?(date_profile) && !strong_bank_evidence?(money, rewound_start_row)
        reasons << "serial_date_without_bank_evidence"
      end
      reasons << "invalid_auto_mapping" unless valid_auto_mapping?(mapping)

      Candidate.new(
        data_start_row: rewound_start_row,
        row_numbers: row_numbers,
        profiles: profiles,
        mapping: mapping,
        score: best_score,
        runner_up_score: runner_up,
        reason_codes: reasons.uniq
      )
    end

    def profile_column(index, row_numbers)
      values = row_numbers.map { |row_number| cell_value(row_number, index) }
      non_blank = values.reject(&:blank?)
      date_hits = non_blank.count { |value| parse_date(value).present? }
      money_hits = non_blank.count { |value| parse_amount(value).present? }
      text_values = non_blank.select { |value| description_like?(value) }
      coverage = ratio(non_blank.size, values.size)
      text_coverage = ratio(text_values.size, values.size)
      average_length = text_values.sum { |value| value.length }.to_f / [ text_values.size, 1 ].max
      diversity = ratio(text_values.uniq.size, text_values.size)

      Profile.new(
        index: index,
        values: values,
        non_blank_count: non_blank.size,
        date_score: ratio(date_hits, values.size),
        money_parse_rate: ratio(money_hits, non_blank.size),
        money_coverage: ratio(money_hits, values.size),
        description_score: (text_coverage * 0.72) + ([ average_length / 48.0, 1.0 ].min * 0.18) + (diversity * 0.10),
        identifier_like: identifier_like?(non_blank, coverage)
      )
    end

    def ranked_date_candidates(profiles)
      candidates = profiles.select { |profile| profile.date_score.positive? }
      explicit_date_candidates = candidates
        .reject { |profile| serial_only_date_profile?(profile) }
        .select { |profile| profile.date_score >= DATE_SCORE_MINIMUM }
      candidates = explicit_date_candidates if explicit_date_candidates.any?

      candidates.sort_by { |profile| -profile.date_score }
    end

    def ranked_description_candidates(profiles)
      profiles.select { |profile| profile.description_score.positive? }.sort_by { |profile| -profile.description_score }
    end

    def money_solutions(profiles, row_numbers, excluded_indices:)
      money_profiles = profiles.reject { |profile| excluded_indices.include?(profile.index) }
        .select do |profile|
          profile.money_parse_rate >= MONEY_PARSE_RATE_MINIMUM &&
            profile.money_coverage >= MONEY_COVERAGE_MINIMUM &&
            !profile.identifier_like
        end
      return [] if money_profiles.blank?

      solutions = direct_money_solutions(money_profiles, row_numbers)
      solutions.concat(split_money_solutions(money_profiles, row_numbers))

      if money_profiles.one?
        only = money_profiles.first
        solutions << MoneySolution.new(
          mapping: { only.index.to_s => "amount" },
          score: only.money_coverage,
          reconciliation: nil,
          coverage: only.money_coverage,
          kind: :direct
        )
      elsif solutions.blank?
        suggested = money_profiles.max_by(&:money_coverage)
        solutions << MoneySolution.new(
          mapping: { suggested.index.to_s => "amount" },
          score: suggested.money_coverage * 0.55,
          reconciliation: nil,
          coverage: suggested.money_coverage,
          kind: :ambiguous
        )
      end

      solutions.sort_by { |solution| -solution.score.to_f }.first(8)
    end

    def direct_money_solutions(money_profiles, row_numbers)
      money_profiles.permutation(2).filter_map do |amount_profile, balance_profile|
        next unless balance_profile.money_coverage >= DENSE_MONEY_COVERAGE_MINIMUM

        reconciliation = reconciliation_for(
          row_numbers,
          amount_values: amount_values(row_numbers, amount_profile.index),
          balance_values: amount_values(row_numbers, balance_profile.index)
        )
        next unless reconciliation.fetch(:comparisons) >= RECONCILIATION_MINIMUM_COMPARISONS
        next unless reconciliation.fetch(:score) >= RECONCILIATION_MINIMUM

        coverage = amount_profile.money_coverage
        score = (reconciliation.fetch(:score) * 0.55) + (coverage * 0.45)
        MoneySolution.new(
          mapping: {
            amount_profile.index.to_s => "amount",
            balance_profile.index.to_s => "balance"
          },
          score: score,
          reconciliation: reconciliation,
          coverage: coverage,
          kind: :direct_with_balance
        )
      end
    end

    def split_money_solutions(money_profiles, row_numbers)
      solutions = []
      money_profiles.combination(2).each do |left, right|
        next unless split_pair?(left, right, row_numbers)

        balance_profiles = money_profiles.reject { |profile| profile.index.in?([ left.index, right.index ]) }
          .select { |profile| profile.money_coverage >= DENSE_MONEY_COVERAGE_MINIMUM }
        next if balance_profiles.blank?

        [ [ left, right ], [ right, left ] ].each do |debit_profile, credit_profile|
          signed_values = split_amount_values(row_numbers, debit_profile.index, credit_profile.index)
          balance_profiles.each do |balance_profile|
            reconciliation = reconciliation_for(
              row_numbers,
              amount_values: signed_values,
              balance_values: amount_values(row_numbers, balance_profile.index)
            )
            next unless reconciliation.fetch(:comparisons) >= RECONCILIATION_MINIMUM_COMPARISONS
            next unless reconciliation.fetch(:score) >= RECONCILIATION_MINIMUM

            coverage = ratio(signed_values.count(&:present?), row_numbers.size)
            score = (reconciliation.fetch(:score) * 0.84) + (coverage * 0.16)
            solutions << MoneySolution.new(
              mapping: {
                debit_profile.index.to_s => "debit",
                credit_profile.index.to_s => "credit",
                balance_profile.index.to_s => "balance"
              },
              score: score,
              reconciliation: reconciliation,
              coverage: coverage,
              kind: :split_with_balance
            )
          end
        end
      end
      solutions
    end

    def split_pair?(left, right, row_numbers)
      pairs = row_numbers.map do |row_number|
        [ parse_amount(cell_value(row_number, left.index)), parse_amount(cell_value(row_number, right.index)) ]
      end
      populated = pairs.select { |left_value, right_value| left_value.present? || right_value.present? }
      return false if populated.blank?

      both = populated.count { |left_value, right_value| left_value.present? && right_value.present? && !left_value.zero? && !right_value.zero? }
      ratio(both, populated.size) <= 0.10 && ratio(populated.size, row_numbers.size) >= 0.65
    end

    def reconciliation_for(row_numbers, amount_values:, balance_values:)
      forward = reconciliation_score(row_numbers, amount_values, balance_values, direction: :forward)
      reverse = reconciliation_score(row_numbers, amount_values, balance_values, direction: :reverse)
      forward.fetch(:score) >= reverse.fetch(:score) ? forward : reverse
    end

    def reconciliation_score(row_numbers, amount_values, balance_values, direction:)
      matches = 0
      comparisons = 0

      if direction == :forward
        (1...row_numbers.size).each do |index|
          amount = amount_values[index]
          balance = balance_values[index]
          prior_balance = balance_values[index - 1]
          next if amount.blank? || balance.blank? || prior_balance.blank?

          comparisons += 1
          matches += 1 if (balance - (prior_balance + amount)).abs <= AMOUNT_TOLERANCE
        end
      else
        (0...(row_numbers.size - 1)).each do |index|
          amount = amount_values[index]
          balance = balance_values[index]
          next_balance = balance_values[index + 1]
          next if amount.blank? || balance.blank? || next_balance.blank?

          comparisons += 1
          matches += 1 if (balance - (next_balance + amount)).abs <= AMOUNT_TOLERANCE
        end
      end

      {
        score: ratio(matches, comparisons),
        matches: matches,
        comparisons: comparisons,
        direction: direction.to_s
      }
    end

    def amount_values(row_numbers, index)
      row_numbers.map { |row_number| parse_amount(cell_value(row_number, index)) }
    end

    def split_amount_values(row_numbers, debit_index, credit_index)
      row_numbers.map do |row_number|
        debit = parse_amount(cell_value(row_number, debit_index))
        credit = parse_amount(cell_value(row_number, credit_index))
        if credit.present? && debit.present?
          credit.abs - debit.abs
        elsif credit.present?
          credit.abs
        elsif debit.present?
          -debit.abs
        end
      end
    end

    def confident_candidate?(candidate)
      candidate.row_numbers.size >= MIN_AUTO_SAMPLE_ROWS &&
        candidate.reason_codes.blank? &&
        valid_auto_mapping?(candidate.mapping)
    end

    def valid_auto_mapping?(mapping)
      roles = mapping.values.map(&:to_s)
      return false unless roles.count("date") == 1 && roles.count("description") == 1
      return false if AUTO_SINGLETON_ROLES.any? { |role| roles.count(role) > 1 }

      direct_amount = roles.count("amount") == 1
      split_amount = roles.count("debit") == 1 || roles.count("credit") == 1
      direct_amount ^ split_amount
    end

    def rewound_data_start_row(mapping, current_start_row)
      roles = mapping.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(index, role), grouped|
        grouped[role.to_s] << index.to_i
      end
      return current_start_row unless roles["date"].one? && roles["description"].one?

      money_indices = roles.values_at("amount", "debit", "credit").flatten
      return current_start_row if money_indices.blank?

      date_index = roles.fetch("date").first
      description_index = roles.fetch("description").first
      (1..current_start_row).find do |row_number|
        parse_date(cell_value(row_number, date_index)).present? &&
          cell_value(row_number, description_index).present? &&
          money_indices.any? { |index| parse_amount(cell_value(row_number, index)).present? }
      end || current_start_row
    end

    def serial_only_date_profile?(profile)
      date_values = profile.values.select { |value| parse_date(value).present? }
      date_values.any? && date_values.all? { |value| bare_excel_serial_date?(value) }
    end

    def bare_excel_serial_date?(value)
      text = value.to_s.strip
      return false unless text.match?(/\A\d+(?:\.\d+)?\z/)

      serial = BigDecimal(text).to_i
      serial >= BasTdk::WorkbookValues::EXCEL_SERIAL_DATE_MIN &&
        serial < BasTdk::WorkbookValues::EXCEL_SERIAL_DATE_MAX
    rescue ArgumentError
      false
    end

    def strong_bank_evidence?(money, data_start_row)
      reconciled = money.reconciliation.present? &&
        money.reconciliation.fetch(:comparisons, 0) >= RECONCILIATION_MINIMUM_COMPARISONS &&
        money.reconciliation.fetch(:score, 0.0) >= RECONCILIATION_MINIMUM
      reconciled || strong_bank_header_evidence?(data_start_row)
    end

    def strong_bank_header_evidence?(data_start_row)
      header_row = inferred_header_row(data_start_row)
      return false if header_row.blank?

      roles = recognized_header_roles(header_row)
      roles.count("date") == 1 &&
        roles.count("description") == 1 &&
        roles.any? { |role| role.in?(%w[amount debit credit]) }
    end

    def suggested_mapping(mapping, profiles, data_start_row)
      suggested = mapping.dup
      header_row = inferred_header_row(data_start_row)

      profiles.each do |profile|
        key = profile.index.to_s
        source_header = header_row.present? ? cell_value(header_row, profile.index) : ""
        role = header_role(source_header)
        if role.present?
          suggested[key] = role
          next
        end
        next if suggested.key?(key)

        suggested[key] = profile.non_blank_count.positive? ? "keep" : "ignore"
      end
      suggested
    end

    def inferred_header_row(data_start_row)
      return if data_start_row <= 1

      previous = data_start_row - 1
      values = column_indices.map { |index| cell_value(previous, index) }
      alpha_count = values.count { |value| value.match?(/[[:alpha:]]/) }
      known_roles = values.filter_map { |value| header_role(value) }
      previous if alpha_count >= 2 || known_roles.any?
    end

    def recognized_header_roles(row_number)
      column_indices.filter_map { |index| header_role(cell_value(row_number, index)) }
    end

    def header_role(value)
      normalized = normalize_header(value)
      return if normalized.blank?
      return "date" if normalized.match?(/\A(?:date|transaction date|txn date|value date|posting date|posted date)\z/)
      return "description" if normalized.match?(/\A(?:description|transaction description|transaction details|details|narrative|narration|particulars|memo)\z/)
      return "debit" if normalized.match?(/\A(?:debit|debits|debit amount|withdrawal|withdrawals|withdrawal amount|paid out|money out|dr|dr amount)\z/)
      return "credit" if normalized.match?(/\A(?:credit|credits|credit amount|deposit|deposits|deposit amount|paid in|money in|cr|cr amount)\z/)
      return "balance" if normalized.match?(/\A(?:balance|running balance|account balance|current balance)\z/)
      return "amount" if normalized.match?(/\A(?:amount|transaction amount|signed amount)\z/)
      return "category" if normalized.in?(%w[category categories])
      return "gst" if normalized.in?([ "gst", "gst code", "tax" ])
      "details" if normalized == "extra details"
    end

    def result_for(candidate, decision:)
      header_row = inferred_header_row(candidate.data_start_row)
      Result.new(
        decision: decision,
        header_row_number: header_row,
        data_start_row: candidate.data_start_row,
        mapping: candidate.mapping,
        confidence: candidate.score.round(4),
        reason_codes: candidate.reason_codes,
        columns: column_metadata(candidate, header_row),
        preview_rows: preview_rows(candidate.data_start_row),
        max_row: max_row,
        max_column: max_column
      )
    end

    def column_metadata(candidate, header_row)
      candidate.profiles.map do |profile|
        source_header = header_row.present? ? cell_value(header_row, profile.index) : ""
        {
          "index" => profile.index,
          "number" => profile.index + 1,
          "letter" => column_letter(profile.index + 1),
          "source_header" => source_header,
          "label" => column_label(profile.index, source_header),
          "samples" => profile.values.reject(&:blank?).uniq.first(SAMPLE_VALUE_LIMIT).map { |value| bounded(value) },
          "suggested_role" => candidate.mapping.fetch(profile.index.to_s, "ignore"),
          "scores" => {
            "date" => profile.date_score.round(4),
            "description" => profile.description_score.round(4),
            "money_parse_rate" => profile.money_parse_rate.round(4),
            "money_coverage" => profile.money_coverage.round(4)
          },
          "identifier_like" => profile.identifier_like
        }
      end
    end

    def preview_rows(data_start_row)
      start_row = inferred_header_row(data_start_row) || data_start_row
      meaningful_row_numbers_from(start_row, limit: PREVIEW_ROW_LIMIT).map do |row_number|
        {
          "row_number" => row_number,
          "values" => column_indices.map { |index| bounded(cell_value(row_number, index)) }
        }
      end
    end

    def review_data_start_row
      first_row = candidate_start_rows.first || 1
      roles = recognized_header_roles(first_row)
      bank_roles = roles & %w[date description amount debit credit balance]
      header_like = bank_roles.uniq.size >= 2 &&
        (bank_roles.include?("date") || bank_roles.any? { |role| role.in?(%w[amount debit credit]) })
      return first_row unless header_like

      meaningful_row_numbers_from(first_row + 1, limit: 1).first || first_row
    end

    def plausible_for_manual_review?(profiles, row_numbers, data_start_row)
      header_row = inferred_header_row(data_start_row)
      meaningful_row_count = row_numbers.size + (header_row.present? && !row_numbers.include?(header_row) ? 1 : 0)
      return false if column_indices.size < 3 || meaningful_row_count < 2

      header_roles = header_row.present? ? recognized_header_roles(header_row) : []
      bank_header_roles = header_roles & %w[date description amount debit credit balance]
      header_signal = bank_header_roles.include?("date") &&
        bank_header_roles.any? { |role| role.in?(%w[description amount debit credit balance]) }
      return true if header_signal

      date_indices = profiles.select { |profile| profile.values.any? { |value| parse_date(value).present? } }.map(&:index)
      money_indices = profiles.select { |profile| profile.values.any? { |value| parse_amount(value).present? } }.map(&:index)
      date_indices.any? do |date_index|
        money_indices.any? do |money_index|
          next false if money_index == date_index

          profiles.any? do |profile|
            profile.index != date_index && profile.index != money_index && profile.non_blank_count.positive?
          end
        end
      end
    end

    def review_result_without_candidate
      data_start_row = review_data_start_row
      row_numbers = meaningful_row_numbers_from(data_start_row, limit: PROFILE_ROW_LIMIT)
      profiles = column_indices.map { |index| profile_column(index, row_numbers) }
      candidate = Candidate.new(
        data_start_row: data_start_row,
        row_numbers: row_numbers,
        profiles: profiles,
        mapping: suggested_mapping({}, profiles, data_start_row),
        score: 0.0,
        runner_up_score: 0.0,
        reason_codes: [ "required_columns_not_detected" ]
      )
      decision = plausible_for_manual_review?(profiles, row_numbers, data_start_row) ? :needs_mapping : :reject
      result_for(candidate, decision: decision)
    end

    def empty_result
      Result.new(
        decision: :reject,
        header_row_number: nil,
        data_start_row: 1,
        mapping: {},
        confidence: 0.0,
        reason_codes: [ "insufficient_columns" ],
        columns: [],
        preview_rows: [],
        max_row: max_row,
        max_column: max_column
      )
    end

    def materially_different?(left, right)
      right.present? && left != right
    end

    def meaningful_row_numbers_from(start_row, limit:)
      return [] if start_row.to_i < 1 || start_row.to_i > max_row || limit.to_i < 1

      (start_row..max_row).lazy.select { |row_number| meaningful_row?(row_number) }.first(limit)
    end

    def meaningful_row?(row_number)
      column_indices.any? { |index| cell_value(row_number, index).present? }
    end

    def transaction_shaped_row?(row_number)
      values = column_indices.map { |index| cell_value(row_number, index) }
      values.any? { |value| parse_date(value).present? } &&
        values.any? { |value| description_like?(value) } &&
        values.any? { |value| parse_amount(value).present? }
    end

    def cell_value(row_number, zero_based_index)
      @cell_value_cache ||= {}
      key = [ row_number, zero_based_index ]
      return @cell_value_cache.fetch(key) if @cell_value_cache.key?(key)

      value = sheet.cell(row_number, zero_based_index + 1)
      normalized = case value
      when nil
        ""
      when Date
        value.iso8601
      when Time, DateTime
        value.to_date.iso8601
      else
        value.to_s.strip
      end
      @cell_value_cache[key] = normalized
    end

    def parse_date(value)
      BasTdk::WorkbookValues.parse_date(value)
    end

    def parse_amount(value)
      BasTdk::WorkbookValues.parse_amount(value)
    end

    def description_like?(value)
      text = value.to_s.strip
      text.present? &&
        text.match?(/[[:alpha:]]/) &&
        parse_date(text).blank? &&
        parse_amount(text).blank?
    end

    def identifier_like?(values, coverage)
      return false if values.blank? || coverage < DENSE_MONEY_COVERAGE_MINIMUM

      normalized = values.map { |value| value.to_s.delete(" ,") }
      long_integers = normalized.count { |value| value.match?(/\A\d{8,}\z/) }
      ratio(long_integers, normalized.size) >= 0.90 && ratio(normalized.uniq.size, normalized.size) <= 0.35
    end

    def normalize_header(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
    end

    def column_label(index, source_header)
      column = "Column #{column_letter(index + 1)}"
      source_header.present? ? "#{column} - #{source_header}" : "#{column} - no header"
    end

    def column_letter(number)
      letters = +""
      current = number.to_i
      while current.positive?
        current -= 1
        letters.prepend((65 + (current % 26)).chr)
        current /= 26
      end
      letters
    end

    def bounded(value)
      value.to_s.first(240)
    end

    def ratio(numerator, denominator)
      return 0.0 if denominator.to_i.zero?

      numerator.to_f / denominator.to_f
    end
  end
end
