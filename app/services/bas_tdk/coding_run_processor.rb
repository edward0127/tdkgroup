require "bigdecimal"

module BasTdk
  class CodingRunProcessor
    class ProcessingError < StandardError; end

    FUZZY_MATCH_THRESHOLD = 0.94
    FUZZY_MATCH_MARGIN = 0.03
    MAX_FUZZY_CANDIDATES = 250
    STANDARD_GST_RATIO = BigDecimal("1") / 11
    STANDARD_GST_RATIO_TOLERANCE = BigDecimal("0.005")
    TIGHT_GST_RATIO_SPREAD = BigDecimal("0.0025")

    ReferenceProfile = Struct.new(
      :normalized_description,
      :direction,
      :category,
      :gst_ratio,
      :gst_treatment,
      :gst_consensus_status,
      :representative,
      :occurrences,
      keyword_init: true
    )

    Proposal = Struct.new(
      :category,
      :gst_amount,
      :gst_treatment,
      :category_source,
      :gst_source,
      :category_confidence,
      :gst_confidence,
      :category_review_required,
      :gst_review_required,
      :warning_codes,
      :explanation,
      :reference_source_row_number,
      :reference_snapshot,
      :metadata,
      keyword_init: true
    )

    def initialize(coding_run:, actor_username: "admin")
      @coding_run = coding_run
      @actor_username = actor_username.to_s.presence || "admin"
      @target_workbook = coding_run.target_workbook
      @bas_job = coding_run.bas_job
    end

    def call
      return supersede!(stale_reason) if stale_reason

      reference_result = read_reference
      return persist_reference_terminal_result(reference_result) unless reference_result.success?

      target_rows = @target_workbook.rows.ordered.to_a
      exact_profiles, fuzzy_index = build_reference_indexes(reference_result.rows)
      previous_codings = previous_codings_for(target_rows)
      proposals = target_rows.to_h do |row|
        [ row.id, proposal_for(row, exact_profiles, fuzzy_index) ]
      end

      apply_results!(
        target_rows: target_rows,
        proposals: proposals,
        previous_codings: previous_codings,
        reference_result: reference_result
      )
    end

    private

    def read_reference
      return empty_reference_result unless @coding_run.reference_file.attached?

      result = nil
      @coding_run.reference_file.open(tmpdir: Rails.root.join("tmp").to_s) do |file|
        result = BasTdk::ReferenceWorkbookReader.new(
          path: file.path,
          source_filename: @coding_run.source_filename.presence || @coding_run.reference_file.filename.to_s,
          mapping_override: reference_mapping_override
        ).call
      end
      result
    end

    def reference_mapping_override
      metadata_override = @coding_run.metadata.to_h["column_mapping_override"]
      override = metadata_override.is_a?(Hash) ? metadata_override.deep_stringify_keys : {}
      confirmed_mapping = @coding_run.column_mapping.to_h
      if confirmed_mapping.present?
        override = override.merge(
          "header_row_number" => @coding_run.header_row_number,
          "data_start_row" => @coding_run.data_start_row,
          "columns" => confirmed_mapping
        ).compact
      end
      override
    end

    def empty_reference_result
      BasTdk::ReferenceWorkbookReader::Result.new(
        status: "processed",
        rows: [],
        original_headers: [],
        column_mapping: {},
        metadata: { "reference_status" => "not_provided" },
        errors: []
      )
    end

    def persist_reference_terminal_result(result)
      attributes = reference_result_attributes(result).merge(
        processing_finished_at: Time.current,
        ruleset_version: BasTdk::CodingRuleEngine::RULESET_VERSION,
        row_errors: result.errors,
        metadata: @coding_run.metadata.to_h.merge(result.metadata.to_h)
      )

      if result.needs_mapping?
        @coding_run.update!(attributes.merge(status: "needs_mapping"))
      else
        @coding_run.update!(attributes.merge(status: "failed"))
      end
      @coding_run
    end

    def build_reference_indexes(rows)
      grouped = rows.group_by { |row| [ row.normalized_description, row.direction ] }
      profiles = grouped.each_with_object({}) do |((normalized, direction), candidates), result|
        next unless BasTdk::DescriptionNormalizer.matchable?(normalized)

        categories = candidates.map { |row| row.category.to_s.strip }.uniq
        next unless categories.one? && categories.first.present?

        gst_ratio, gst_treatment, gst_consensus_status = gst_consensus(candidates)

        representative = candidates.min_by(&:source_row_number)
        result[[ normalized, direction ]] = ReferenceProfile.new(
          normalized_description: normalized,
          direction: direction,
          category: categories.first,
          gst_ratio: gst_ratio,
          gst_treatment: gst_treatment,
          gst_consensus_status: gst_consensus_status,
          representative: representative,
          occurrences: candidates.length
        )
      end

      fuzzy_index = Hash.new { |hash, token| hash[token] = [] }
      profiles.each_value do |profile|
        profile.normalized_description.split.uniq.each { |token| fuzzy_index[token] << profile }
      end
      [ profiles, fuzzy_index ]
    end

    def gst_consensus(candidates)
      rows_with_ratio = candidates.select { |row| row.gst_ratio.present? }
      return [ nil, "needs_review", "missing" ] if rows_with_ratio.empty?
      return [ nil, "needs_review", "incomplete" ] unless rows_with_ratio.length == candidates.length

      ratios = rows_with_ratio.map(&:gst_ratio).sort
      treatments = rows_with_ratio.map { |row| row.gst_treatment.to_s }.uniq
      if ratios.all?(&:zero?)
        return [ BigDecimal("0"), treatments.first, "zero" ] if treatments.one?

        return [ nil, "needs_review", "conflict" ]
      end

      if treatments == [ "taxable" ] && ratios.all? { |ratio| (ratio - STANDARD_GST_RATIO).abs <= STANDARD_GST_RATIO_TOLERANCE }
        return [ STANDARD_GST_RATIO, "taxable", "standard_taxable" ]
      end

      spread = ratios.last - ratios.first
      if treatments.one? && spread.abs <= TIGHT_GST_RATIO_SPREAD
        return [ median_ratio(ratios), treatments.first, "tight_ratio" ]
      end

      [ nil, "needs_review", "conflict" ]
    end

    def median_ratio(sorted_ratios)
      middle = sorted_ratios.length / 2
      return sorted_ratios.fetch(middle) if sorted_ratios.length.odd?

      (sorted_ratios.fetch(middle - 1) + sorted_ratios.fetch(middle)) / 2
    end

    def proposal_for(row, exact_profiles, fuzzy_index)
      row_data = row.row_data.to_h
      description = row_data["Description"].to_s
      amount = parse_decimal(row_data["Amount"])
      normalized = BasTdk::DescriptionNormalizer.call(description)
      direction = direction_for(amount)

      profile = exact_profiles[[ normalized, direction ]]
      return previous_quarter_proposal(profile, amount, exact: true, similarity: 1.0) if profile

      fuzzy_profile, similarity = fuzzy_profile_for(normalized, direction, fuzzy_index)
      return previous_quarter_proposal(fuzzy_profile, amount, exact: false, similarity: similarity) if fuzzy_profile

      rule_proposal(description, amount)
    end

    def fuzzy_profile_for(normalized, direction, fuzzy_index)
      return [ nil, nil ] unless BasTdk::DescriptionNormalizer.matchable?(normalized)

      candidate_counts = normalized.split.uniq.each_with_object(Hash.new(0)) do |token, counts|
        fuzzy_index.fetch(token, []).each { |profile| counts[profile] += 1 if profile.direction == direction }
      end
      candidates = candidate_counts
        .sort_by { |profile, shared| [ -shared, profile.normalized_description ] }
        .first(MAX_FUZZY_CANDIDATES)
        .map(&:first)
      scored = candidates.map do |profile|
        [ profile, BasTdk::DescriptionNormalizer.similarity(normalized, profile.normalized_description) ]
      end.sort_by { |profile, score| [ -score, profile.normalized_description ] }
      best = scored.first
      return [ nil, nil ] unless best && best.last >= FUZZY_MATCH_THRESHOLD

      second_score = scored.second&.last.to_f
      return [ nil, nil ] if second_score >= best.last - FUZZY_MATCH_MARGIN

      best
    end

    def previous_quarter_proposal(profile, amount, exact:, similarity:)
      source = exact ? "previous_quarter_exact" : "previous_quarter_fuzzy"
      gst_amount = if amount && profile.gst_ratio
        (amount * profile.gst_ratio).round(2)
      end
      warnings = []
      warnings << "fuzzy_previous_quarter_match" unless exact
      if profile.gst_ratio.nil?
        warnings << (profile.gst_consensus_status == "conflict" ? "historical_gst_conflict" : "historical_gst_missing")
      end
      review_required = !exact

      Proposal.new(
        category: profile.category,
        gst_amount: gst_amount,
        gst_treatment: profile.gst_ratio.nil? ? "needs_review" : profile.gst_treatment,
        category_source: source,
        gst_source: gst_amount.nil? ? "unmatched" : source,
        category_confidence: exact ? 100.0 : (similarity * 100).round(2),
        gst_confidence: gst_amount.nil? ? 0.0 : (exact ? 100.0 : (similarity * 100).round(2)),
        category_review_required: review_required,
        gst_review_required: review_required || gst_amount.nil?,
        warning_codes: warnings,
        explanation: if exact && profile.gst_ratio
                       "Matched the same normalized description and transaction direction in the reference workbook. Historical category and GST treatment were consistent."
                     elsif exact
                       "Matched the same normalized description and transaction direction with a consistent historical category. Historical GST was missing or conflicted, so GST was left for review."
                     else
                       "High-similarity previous-quarter match (#{(similarity * 100).round(1)}%). Review both fields before relying on it."
                     end,
        reference_source_row_number: profile.representative.source_row_number,
        reference_snapshot: reference_snapshot(profile),
        metadata: {
          "match_type" => exact ? "exact" : "fuzzy",
          "match_similarity" => similarity.round(6),
          "reference_occurrences" => profile.occurrences,
          "gst_consensus_status" => profile.gst_consensus_status
        }
      )
    end

    def reference_snapshot(profile)
      row = profile.representative
      row.snapshot.to_h.merge(
        "source_row_number" => row.source_row_number,
        "normalized_description" => row.normalized_description,
        "direction" => row.direction,
        "gst_amount" => row.gst_amount&.to_s("F"),
        "gst_ratio" => profile.gst_ratio&.to_s("F"),
        "gst_treatment" => profile.gst_treatment,
        "gst_consensus_status" => profile.gst_consensus_status
      )
    end

    def rule_proposal(description, amount)
      rule = BasTdk::CodingRuleEngine.new(description: description, amount: amount).call
      source = rule.rule_id == "unmatched" ? "unmatched" : "rule"
      Proposal.new(
        category: rule.category,
        gst_amount: rule.gst_amount,
        gst_treatment: rule.gst_treatment,
        category_source: rule.category.present? ? source : "unmatched",
        gst_source: rule.gst_amount.nil? ? "unmatched" : source,
        category_confidence: rule.category_confidence,
        gst_confidence: rule.gst_confidence,
        category_review_required: rule.category_review_required,
        gst_review_required: rule.gst_review_required,
        warning_codes: rule.warning_codes,
        explanation: rule.explanation,
        reference_snapshot: {},
        metadata: { "rule_id" => rule.rule_id }
      )
    end

    def previous_codings_for(rows)
      row_ids = rows.map(&:id)
      return {} if row_ids.empty?

      BasTdkRowCoding
        .where(bas_tdk_workbook_row_id: row_ids)
        .where.not(bas_tdk_coding_run_id: @coding_run.id)
        .order(created_at: :desc, id: :desc)
        .each_with_object({}) do |coding, result|
          result[coding.bas_tdk_workbook_row_id] ||= coding
        end
    end

    def apply_results!(target_rows:, proposals:, previous_codings:, reference_result:)
      changed = false
      counts = { rows: 0, suggestions: 0, warnings: 0, reviewed: 0 }

      BasTdkCodingRun.transaction do
        @coding_run.lock!
        @target_workbook.lock!
        reason = stale_reason(lock: true)
        if reason
          @coding_run.update!(
            status: "superseded",
            superseded_at: Time.current,
            processing_finished_at: Time.current,
            row_errors: [ reason ],
            metadata: @coding_run.metadata.to_h.merge("superseded_reason" => reason)
          )
          return @coding_run
        end

        @coding_run.row_codings.delete_all
        target_rows.each do |row|
          row.lock!
          proposal = proposals.fetch(row.id)
          coding_attributes, row_changed = resolved_attributes(
            row: row,
            proposal: proposal,
            previous_coding: previous_codings[row.id]
          )
          changed ||= row_changed
          @coding_run.row_codings.create!(coding_attributes.merge(workbook_row: row))

          counts[:rows] += 1
          counts[:suggestions] += 1 if coding_attributes[:suggested_category].present? || coding_attributes[:suggested_gst_amount].present?
          counts[:warnings] += 1 if coding_attributes[:category_review_required] || coding_attributes[:gst_review_required]
          counts[:reviewed] += 1 if coding_attributes[:review_status].in?(BasTdkRowCoding::REVIEWED_STATUS_VALUES)
        end

        @target_workbook.invalidate_export! if changed
        @coding_run.update!(
          reference_result_attributes(reference_result).merge(
            status: "processed",
            processing_finished_at: Time.current,
            processed_at: Time.current,
            ruleset_version: BasTdk::CodingRuleEngine::RULESET_VERSION,
            row_errors: [],
            reference_row_count: reference_result.rows.length,
            row_count: counts.fetch(:rows),
            suggestion_count: counts.fetch(:suggestions),
            warning_count: counts.fetch(:warnings),
            reviewed_count: counts.fetch(:reviewed),
            metadata: @coding_run.metadata.to_h.merge(
              reference_result.metadata.to_h,
              "target_workbook_id" => @target_workbook.id,
              "target_workbook_version" => @target_workbook.version_number,
              "ruleset_version" => BasTdk::CodingRuleEngine::RULESET_VERSION,
              "row_data_changed" => changed
            )
          )
        )
      end
      @coding_run
    end

    def resolved_attributes(row:, proposal:, previous_coding:)
      row_data = row.row_data.to_h.deep_dup
      original_category = row_data["Category"].to_s
      original_gst = row_data["GST"].to_s
      row_updated_at_before_apply = row.updated_at
      category_manual = manual_field?("Category", original_category, previous_coding)
      gst_manual = manual_field?("GST", original_gst, previous_coding)
      warnings = proposal.warning_codes.to_a.dup

      if category_manual
        category = original_category.strip
        category_source = category.present? ? "manual" : "unmatched"
        category_confidence = category.present? ? 100.0 : 0.0
        category_review_required = category.blank?
      else
        category = proposal.category
        category_source = proposal.category_source
        category_confidence = proposal.category_confidence
        category_review_required = proposal.category_review_required
        row_data["Category"] = category.to_s
      end

      if gst_manual
        gst_amount = gst_amount_from_text(original_gst, parse_decimal(row_data["Amount"]))
        gst_source = gst_amount.nil? ? "unmatched" : "manual"
        gst_confidence = gst_amount.nil? ? 0.0 : 100.0
        gst_review_required = gst_amount.nil?
        gst_treatment = gst_treatment_from_text(original_gst, gst_amount)
      else
        gst_amount = proposal.gst_amount
        gst_source = proposal.gst_source
        gst_confidence = proposal.gst_confidence
        gst_review_required = proposal.gst_review_required
        gst_treatment = proposal.gst_treatment
        row_data["GST"] = gst_amount.nil? ? "" : format_decimal(gst_amount)
      end

      warnings.delete("category_unclassified") if category_manual && category.present?
      warnings.delete("gst_unclassified") if gst_manual && gst_amount.present?
      warnings << "category_unclassified" if category.blank?
      warnings << "gst_unclassified" if gst_amount.nil?
      review_required = category_review_required || gst_review_required
      row_changed = row_data != row.row_data.to_h
      row.update!(row_data: row_data) if row_changed

      attributes = {
        suggested_category: category.presence,
        suggested_gst_amount: gst_amount,
        gst_treatment: gst_treatment.presence || "unknown",
        category_source: category_source,
        gst_source: gst_source,
        category_confidence: category_confidence,
        gst_confidence: gst_confidence,
        category_review_required: category_review_required,
        gst_review_required: gst_review_required,
        review_status: review_required ? "needs_review" : "proposed",
        warning_codes: warnings.uniq,
        explanation: manual_explanation(proposal.explanation, category_manual, gst_manual),
        reference_source_row_number: proposal.reference_source_row_number,
        reference_snapshot: proposal.reference_snapshot.to_h,
        metadata: proposal.metadata.to_h.merge(
          "original_category" => original_category,
          "original_gst" => original_gst,
          "category_preserved_as_manual" => category_manual,
          "gst_preserved_as_manual" => gst_manual,
          "target_row_updated_at_before_apply" => row_updated_at_before_apply&.iso8601(6)
        )
      }
      [ attributes, row_changed ]
    end

    def manual_field?(field, current_value, previous_coding)
      return current_value.to_s.strip.present? if previous_coding.blank?
      source = field == "Category" ? previous_coding.category_source : previous_coding.gst_source
      return true if source == "manual"

      suggested = if field == "Category"
        previous_coding.suggested_category.to_s
      else
        previous_coding.suggested_gst_amount
      end
      values_equivalent?(field, current_value, suggested) ? false : true
    end

    def values_equivalent?(field, current, suggested)
      if field == "Category"
        current.to_s.strip == suggested.to_s.strip
      else
        current_decimal = gst_amount_from_text(current, nil)
        suggested_decimal = parse_decimal(suggested)
        return true if current.to_s.strip.blank? && suggested_decimal.nil?

        current_decimal.present? && suggested_decimal.present? && current_decimal == suggested_decimal
      end
    end

    def gst_amount_from_text(value, amount)
      text = value.to_s.strip
      return if text.blank?

      normalized = ActiveSupport::Inflector.transliterate(text).downcase.gsub(/[^a-z0-9]+/, " ").strip
      return BigDecimal("0") if normalized.match?(/\b(?:gst free|no gst|input taxed|bas excluded|not reportable|n t)\b/)
      return (amount / 11).round(2) if amount && normalized.match?(/\b(?:gst included|taxable|gst|10|1 11)\b/)

      parse_decimal(text)
    end

    def gst_treatment_from_text(value, numeric)
      normalized = ActiveSupport::Inflector.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, " ").strip
      return "input_taxed" if normalized.include?("input taxed")
      return "bas_excluded" if normalized.match?(/\b(?:bas excluded|not reportable)\b/)
      return "no_gst" if numeric&.zero?
      return "taxable" if numeric

      "unknown"
    end

    def manual_explanation(original, category_manual, gst_manual)
      preserved = []
      preserved << "Category" if category_manual
      preserved << "GST" if gst_manual
      return original if preserved.empty?

      "#{original} Preserved existing manual #{preserved.to_sentence} without overwriting."
    end

    def reference_result_attributes(result)
      {
        source_filename: @coding_run.source_filename,
        sheet_name: result.sheet_name,
        header_row_number: result.header_row_number,
        data_start_row: result.data_start_row,
        original_headers: result.original_headers.to_a,
        column_mapping: result.column_mapping.to_h,
        reference_row_count: result.rows.to_a.length
      }
    end

    def stale_reason(lock: false)
      return "The target bank statement is no longer the active processed workbook." unless @target_workbook&.processed?

      active_scope = @bas_job.tdk_workbooks.active_processed
      active_scope = active_scope.lock if lock
      active = active_scope.first
      return "The target bank statement is no longer the active processed workbook." unless active&.id == @target_workbook.id

      newer = @bas_job.tdk_coding_runs
        .where(target_workbook_id: @target_workbook.id)
        .where("version_number > ?", @coding_run.version_number)
        .where.not(status: %w[failed superseded])
        .exists?
      "A newer Category/GST coding run has replaced this run." if newer
    end

    def supersede!(reason)
      @coding_run.update!(
        status: "superseded",
        superseded_at: Time.current,
        processing_finished_at: Time.current,
        row_errors: [ reason ],
        metadata: @coding_run.metadata.to_h.merge("superseded_reason" => reason)
      )
      @coding_run
    end

    def parse_decimal(value)
      return value if value.is_a?(BigDecimal)

      text = value.to_s.strip
      return if text.blank?

      negative = text.match?(/\A\(.*\)\z/) || text.end_with?("-") || text.match?(/\bDR\z/i)
      positive_credit = text.match?(/\bCR\z/i)
      normalized = text.gsub(/[,$\s()]/, "").sub(/(?:CR|DR)\z/i, "").sub(/-\z/, "")
      return unless normalized.match?(/\A[+-]?\d+(?:\.\d+)?\z/)

      number = BigDecimal(normalized)
      number = -number.abs if negative
      number = number.abs if positive_credit
      number
    rescue ArgumentError
      nil
    end

    def direction_for(amount)
      return "credit" if amount&.positive?
      return "debit" if amount&.negative?

      "zero"
    end

    def format_decimal(value)
      format("%.2f", value.to_d)
    end
  end
end
