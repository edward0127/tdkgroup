require "bigdecimal"
require "digest"

module BasTdk
  class CodingRunProcessor
    class ProcessingError < StandardError; end

    FUZZY_MATCH_THRESHOLD = 0.94
    FUZZY_MATCH_MARGIN = 0.03
    MAX_FUZZY_CANDIDATES = 250
    MIN_TEMPLATE_SUPPORT = 2
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
      :match_kind,
      :match_key,
      keyword_init: true
    )

    ReferenceIndexes = Struct.new(
      :exact_profiles,
      :fuzzy_index,
      :template_profiles,
      :merchant_profiles,
      :category_vocabulary,
      keyword_init: true
    )

    CATEGORY_VOCABULARY_PATTERNS = {
      "bank_fee" => [ /\Abank\s+fees?\z/i, /\Abank\s+charges?\z/i ],
      "ato_payment" => [ /\Aato\z/i, /\Atax\s+payments?\z/i ],
      "superannuation" => [ /\Asuper(?:annuation|\s+paid)?\z/i ],
      "merchant_service_fee" => [ /\Amerchant\s+fees?\z/i, /\Acard\s+processing\s+fees?\z/i ],
      "printing_stationery" => [ /\Astationery\z/i, /\Aprinting\z/i ],
      "office_expenses" => [ /\Aoffice\s+expenses?\z/i, /\Astationery\z/i ],
      "packaging" => [ /\Apackaging\z/i, /\Apacking\s+supplies?\z/i ],
      "equipment" => [ /\Areplacements?\z/i, /\Aequipment(?:\s*(?:&|and)\s*assets?)?\z/i, /\Aassets?\z/i ],
      "meals_entertainment" => [ /\Ameals?(?:\s*(?:&|and)\s*entertainment)?\z/i, /\Astaff\s+amen(?:it|tit)(?:y|ies)\z/i ],
      "staff_amenities" => [ /\Astaff\s+amen(?:it|tit)(?:y|ies)\z/i ],
      "rent_property" => [ /\A(?:rent|rental)(?:\s+(?:expense|exp|property))?\z/i, /\Aproperty\s+(?:rent|expense)\z/i ],
      "repairs" => [ /\Arepairs?(?:\s*(?:&|and)\s*maintenance)?\z/i, /\Amaintenance(?:\s*(?:&|and)\s*repairs?)?\z/i ]
    }.freeze
    GST_HISTORY_SUPPRESSION_RULE_IDS = %w[
      mixed_retailer
      insurance_registration
      meals_entertainment
      staff_amenities
      international
      water_supply
    ].freeze

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
      reference_indexes = build_reference_indexes(reference_result.rows)
      validation_offset_row_ids = paired_validation_offset_row_ids(target_rows)
      previous_codings = previous_codings_for(target_rows)
      proposals = target_rows.to_h do |row|
        [
          row.id,
          proposal_for(
            row,
            reference_indexes,
            paired_validation_offset: validation_offset_row_ids.key?(row.id)
          )
        ]
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
        next if normalized.blank?

        profile = reference_profile(
          candidates,
          normalized_description: normalized,
          direction: direction,
          match_kind: "exact",
          match_key: normalized
        )
        result[[ normalized, direction ]] = profile if profile
      end

      fuzzy_index = Hash.new { |hash, token| hash[token] = [] }
      profiles.each_value do |profile|
        next unless BasTdk::DescriptionNormalizer.matchable?(profile.normalized_description)

        profile.normalized_description.split.uniq.each { |token| fuzzy_index[token] << profile }
      end

      template_profiles = evidence_profiles(
        rows,
        key_method: :template_keys,
        match_kind: "template",
        minimum_support: MIN_TEMPLATE_SUPPORT
      )
      merchant_profiles = evidence_profiles(
        rows,
        key_method: :merchant_keys,
        match_kind: "merchant",
        minimum_support: 1
      )

      ReferenceIndexes.new(
        exact_profiles: profiles,
        fuzzy_index: fuzzy_index,
        template_profiles: template_profiles,
        merchant_profiles: merchant_profiles,
        category_vocabulary: rows.map { |row| row.category.to_s.strip }.compact_blank.tally
      )
    end

    def evidence_profiles(rows, key_method:, match_kind:, minimum_support:)
      grouped = Hash.new { |hash, key| hash[key] = [] }
      rows.each do |row|
        BasTdk::TransactionFingerprint.call(row.description).public_send(key_method).each do |key|
          grouped[[ key, row.direction ]] << row
        end
      end

      grouped.each_with_object({}) do |((key, direction), candidates), profiles|
        next if candidates.length < minimum_support

        profile = reference_profile(
          candidates,
          normalized_description: candidates.first.normalized_description,
          direction: direction,
          match_kind: match_kind,
          match_key: key
        )
        profiles[[ key, direction ]] = profile if profile
      end
    end

    def reference_profile(candidates, normalized_description:, direction:, match_kind:, match_key:)
      category_groups = candidates.group_by { |row| normalized_category(row.category) }.reject { |category, _| category.blank? }
      return unless category_groups.one?

      category_rows = category_groups.values.first
      category = category_rows.map { |row| row.category.to_s.strip }.tally.max_by { |label, count| [ count, label ] }.first
      gst_ratio, gst_treatment, gst_consensus_status = gst_consensus(candidates)
      representative = candidates.min_by(&:source_row_number)

      ReferenceProfile.new(
        normalized_description: normalized_description,
        direction: direction,
        category: category,
        gst_ratio: gst_ratio,
        gst_treatment: gst_treatment,
        gst_consensus_status: gst_consensus_status,
        representative: representative,
        occurrences: candidates.length,
        match_kind: match_kind,
        match_key: match_key
      )
    end

    def normalized_category(value)
      ActiveSupport::Inflector.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, " ").squish
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

    def proposal_for(row, reference_indexes, paired_validation_offset: false)
      row_data = row.row_data.to_h
      description = row_data["Description"].to_s
      amount = parse_decimal(row_data["Amount"])
      normalized = BasTdk::DescriptionNormalizer.call(description)
      direction = direction_for(amount)
      fingerprint = BasTdk::TransactionFingerprint.call(description)

      if paired_validation_offset
        return paired_validation_offset_proposal(reference_indexes.category_vocabulary)
      end

      profile = reference_indexes.exact_profiles[[ normalized, direction ]]
      if profile
        return previous_quarter_proposal_with_taxable_fallback(
          profile,
          amount,
          exact: true,
          similarity: 1.0,
          description: description
        )
      end

      fuzzy_profile, similarity = fuzzy_profile_for(normalized, direction, reference_indexes.fuzzy_index)
      if fuzzy_profile
        return previous_quarter_proposal_with_taxable_fallback(
          fuzzy_profile,
          amount,
          exact: false,
          similarity: similarity,
          description: description
        )
      end

      merchant_evidence = evidence_profile_for(
        fingerprint.merchant_keys,
        direction,
        reference_indexes.merchant_profiles
      )
      template_evidence = evidence_profile_for(
        fingerprint.template_keys,
        direction,
        reference_indexes.template_profiles
      )
      combined_evidence = combine_evidence(merchant_evidence, template_evidence)
      return conflicting_history_proposal if combined_evidence == :conflict

      if combined_evidence
        return previous_quarter_proposal_with_taxable_fallback(
          combined_evidence,
          amount,
          exact: false,
          similarity: evidence_confidence(combined_evidence),
          description: description
        )
      end

      rule_proposal(description, amount, reference_indexes.category_vocabulary)
    end

    def paired_validation_offset_row_ids(rows)
      candidates = rows.filter_map do |row|
        data = row.row_data.to_h
        amount = parse_decimal(data["Amount"])
        next if amount.nil? || amount.zero?

        description = data["Description"].to_s
        role = if description.match?(/\b(?:micro|test|verification)\s+deposits?\b/i)
          "validation_deposit"
        elsif description.match?(/\b(?:reversal|reversed)\b/i)
          "reversal"
        end
        next if role.blank?

        {
          row: row,
          amount: amount,
          role: role,
          identity_tokens: validation_identity_tokens(description)
        }
      end

      candidates.group_by { |candidate| candidate.fetch(:amount).abs.round(2).to_s("F") }.each_with_object({}) do |(_amount, group), ids|
        eligible_partners = Hash.new { |hash, row_id| hash[row_id] = [] }

        group.combination(2) do |left, right|
          next if left.fetch(:role) == right.fetch(:role)
          next unless left.fetch(:amount).positive? != right.fetch(:amount).positive?
          next unless strong_validation_identity_match?(left, right)

          left_id = left.fetch(:row).id
          right_id = right.fetch(:row).id
          eligible_partners[left_id] << right_id
          eligible_partners[right_id] << left_id
        end

        eligible_partners.each do |row_id, partner_ids|
          next unless partner_ids.one?

          partner_id = partner_ids.first
          next unless eligible_partners.fetch(partner_id, []).one?
          next unless eligible_partners.fetch(partner_id).first == row_id

          ids[row_id] = true
          ids[partner_id] = true
        end
      end
    end

    def validation_identity_tokens(description)
      ignored = %w[
        account australia business company debit deposit direct fast for from limited
        micro payment reversal reversed services test transfer validation verification
      ]
      BasTdk::DescriptionNormalizer.tokens(description).select do |token|
        token.match?(/\A[a-z]{4,}\z/) && ignored.exclude?(token)
      end
    end

    def strong_validation_identity_match?(left, right)
      shared_tokens = left.fetch(:identity_tokens) & right.fetch(:identity_tokens)
      shared_tokens.length >= 2 || (shared_tokens.one? && shared_tokens.first.length >= 8)
    end

    def paired_validation_offset_proposal(category_vocabulary)
      categories = category_vocabulary.keys.select do |category|
        category.match?(/\A(?:offset|clearing|suspense|transfers?)\z/i)
      end
      category = if categories.map { |candidate| normalized_category(candidate) }.uniq.one?
        categories.max_by { |candidate| [ category_vocabulary.fetch(candidate), candidate ] }
      else
        "Offset"
      end

      Proposal.new(
        category: category,
        gst_amount: nil,
        gst_treatment: "unknown",
        category_source: "rule",
        gst_source: "unmatched",
        category_confidence: 88.0,
        gst_confidence: 0.0,
        category_review_required: true,
        gst_review_required: true,
        warning_codes: [ "rule_suggestion_requires_review", "paired_validation_offset" ],
        explanation: "This equal-and-opposite micro-deposit/reversal pair shares the same counterparty identity. It was suggested as an offset and left highlighted for review.",
        reference_snapshot: {},
        metadata: { "rule_id" => "paired_validation_offset" }
      )
    end

    def evidence_profile_for(keys, direction, profiles)
      candidates = keys.filter_map { |key| profiles[[ key, direction ]] }.uniq
      merge_evidence_profiles(candidates)
    end

    def combine_evidence(*selections)
      compact = selections.compact
      return if compact.empty?
      return :conflict if compact.include?(:conflict)

      merge_evidence_profiles(compact)
    end

    def merge_evidence_profiles(candidates)
      return if candidates.empty?
      return :conflict if candidates.map { |profile| normalized_category(profile.category) }.uniq.many?

      selected = candidates.max_by { |profile| evidence_profile_rank(profile) }
      return selected if compatible_gst_evidence?(candidates)

      selected.dup.tap do |profile|
        profile.gst_ratio = nil
        profile.gst_treatment = "needs_review"
        profile.gst_consensus_status = "conflict"
      end
    end

    def evidence_profile_rank(profile)
      static_key = profile.match_key.to_s.exclude?(":")
      [ profile.occurrences, static_key ? 1 : 0, profile.match_kind == "merchant" ? 1 : 0, profile.match_key.to_s.length ]
    end

    def compatible_gst_evidence?(profiles)
      return false if profiles.any? { |profile| profile.gst_consensus_status == "conflict" }

      ratios = profiles.map(&:gst_ratio)
      return true if ratios.all?(&:nil?)
      return false if ratios.any?(&:nil?)
      return false if profiles.map(&:gst_treatment).uniq.many?

      ratios.max - ratios.min <= TIGHT_GST_RATIO_SPREAD
    end

    def conflicting_history_proposal
      Proposal.new(
        category: nil,
        gst_amount: nil,
        gst_treatment: "needs_review",
        category_source: "unmatched",
        gst_source: "unmatched",
        category_confidence: 0.0,
        gst_confidence: 0.0,
        category_review_required: true,
        gst_review_required: true,
        warning_codes: [ "historical_evidence_conflict" ],
        explanation: "Different merchant or bank-template evidence points to conflicting historical coding. Both fields were left blank for review.",
        reference_snapshot: {},
        metadata: { "match_type" => "evidence_conflict" }
      )
    end

    def evidence_confidence(profile)
      case profile.match_kind
      when "template"
        [ 0.82 + ([ profile.occurrences, 20 ].min * 0.006), 0.94 ].min
      when "merchant"
        [ 0.78 + ([ profile.occurrences, 10 ].min * 0.012), 0.9 ].min
      else
        0.8
      end
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
        normalized_zero((amount * profile.gst_ratio).round(2))
      end
      gst_blank_inherited = profile.gst_consensus_status == "missing"
      warnings = []
      warnings << history_warning_code(profile, exact: exact) if history_warning_code(profile, exact: exact)
      if gst_blank_inherited
        warnings << "historical_gst_blank_inherited"
      elsif profile.gst_ratio.nil?
        warnings << (profile.gst_consensus_status == "conflict" ? "historical_gst_conflict" : "historical_gst_missing")
      end
      review_required = !exact || profile.occurrences == 1
      confidence = exact ? (review_required ? 92.0 : 100.0) : (similarity * 100).round(2)
      gst_source = if gst_amount.present? || gst_blank_inherited
        source
      else
        "unmatched"
      end
      gst_confidence = gst_amount.present? || gst_blank_inherited ? confidence : 0.0
      gst_review_required = gst_blank_inherited ? false : (review_required || gst_amount.nil?)
      explanation = if exact && profile.gst_ratio && !review_required
        "Matched the same normalized description and transaction direction in the reference workbook. Historical category and GST treatment were consistent."
      elsif exact && profile.gst_ratio
        "Matched one same-direction historical transaction. The values were copied, but a single prior example is highlighted for review."
      elsif exact && gst_blank_inherited
        "Matched the same normalized description and transaction direction with a consistent historical category."
      elsif exact
        "Matched the same normalized description and transaction direction with a consistent historical category. Historical GST was missing or conflicted, so GST was left for review."
      elsif profile.match_kind == "template"
        "Matched a same-direction bank-description template used consistently in the reference workbook (#{profile.occurrences} examples). Review the history-derived suggestion before relying on it."
      elsif profile.match_kind == "merchant"
        "Matched a strong merchant identity used consistently in the reference workbook (#{profile.occurrences} #{'example'.pluralize(profile.occurrences)}). Review this cross-description suggestion before relying on it."
      else
        "High-similarity previous-quarter match (#{(similarity * 100).round(1)}%). Review both fields before relying on it."
      end
      if gst_blank_inherited
        explanation = "#{explanation} Historical GST was consistently blank, so the blank GST was inherited without treating it as zero."
      end

      Proposal.new(
        category: profile.category,
        gst_amount: gst_amount,
        gst_treatment: gst_blank_inherited ? "unknown" : (profile.gst_ratio.nil? ? "needs_review" : profile.gst_treatment),
        category_source: source,
        gst_source: gst_source,
        category_confidence: confidence,
        gst_confidence: gst_confidence,
        category_review_required: review_required,
        gst_review_required: gst_review_required,
        warning_codes: warnings,
        explanation: explanation,
        reference_source_row_number: profile.representative.source_row_number,
        reference_snapshot: reference_snapshot(profile),
        metadata: {
          "match_type" => exact ? "exact" : (profile.match_kind.in?(%w[template merchant]) ? profile.match_kind : "fuzzy"),
          "match_similarity" => similarity.round(6),
          "reference_occurrences" => profile.occurrences,
          "gst_consensus_status" => profile.gst_consensus_status
        }.merge(persisted_match_key_metadata(profile.match_key))
      )
    end

    def persisted_match_key_metadata(match_key)
      key = match_key.to_s
      return {} if key.blank?
      return { "match_key" => key } unless key.include?(":")

      {
        "match_key_type" => key.split(":", 2).first,
        "match_key_sha256" => Digest::SHA256.hexdigest(key)
      }
    end

    def previous_quarter_proposal_with_taxable_fallback(profile, amount, exact:, similarity:, description:)
      proposal = previous_quarter_proposal(profile, amount, exact: exact, similarity: similarity)
      return proposal if profile.gst_consensus_status == "missing"

      rule = BasTdk::CodingRuleEngine.new(description: description, amount: amount).call
      if rule.rule_id.in?(GST_HISTORY_SUPPRESSION_RULE_IDS)
        proposal.gst_amount = nil
        proposal.gst_treatment = "needs_review"
        proposal.gst_source = "unmatched"
        proposal.gst_confidence = 0.0
        proposal.gst_review_required = true
        proposal.warning_codes = (proposal.warning_codes.to_a + rule.warning_codes.to_a + [ "historical_gst_suppressed" ]).uniq
        proposal.explanation = "#{proposal.explanation} GST was left blank because this supplier can involve mixed or uncertain GST treatment; check the current tax invoice."
        proposal.metadata = proposal.metadata.to_h.merge("gst_suppressed_by_rule_id" => rule.rule_id)
        return proposal
      end

      return proposal if proposal.gst_amount.present?

      return proposal unless rule.gst_treatment == "taxable" && rule.gst_amount.present?

      proposal.gst_amount = normalized_zero(rule.gst_amount)
      proposal.gst_treatment = "taxable"
      proposal.gst_source = "rule"
      proposal.gst_confidence = rule.gst_confidence
      proposal.gst_review_required = true
      proposal.warning_codes = (proposal.warning_codes.to_a + rule.warning_codes.to_a + [ "gst_rule_fallback" ]).uniq
      proposal.explanation = "#{proposal.explanation} Historical GST was unavailable, so a conservative taxable-expense rule supplied GST for review."
      proposal.metadata = proposal.metadata.to_h.merge("gst_fallback_rule_id" => rule.rule_id)
      proposal
    end

    def history_warning_code(profile, exact:)
      return "single_historical_match" if exact && profile.occurrences == 1
      return if exact

      case profile.match_kind
      when "template" then "historical_template_match"
      when "merchant" then "historical_merchant_match"
      else "fuzzy_previous_quarter_match"
      end
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

    def rule_proposal(description, amount, category_vocabulary = {})
      rule = BasTdk::CodingRuleEngine.new(description: description, amount: amount).call
      source = rule.rule_id == "unmatched" ? "unmatched" : "rule"
      category = category_for_rule(rule, category_vocabulary)
      category_remapped = category.present? && category != rule.category
      Proposal.new(
        category: category,
        gst_amount: normalized_zero(rule.gst_amount),
        gst_treatment: rule.gst_treatment,
        category_source: category.present? ? source : "unmatched",
        gst_source: rule.gst_amount.nil? ? "unmatched" : source,
        category_confidence: rule.category_confidence,
        gst_confidence: rule.gst_confidence,
        category_review_required: rule.category_review_required,
        gst_review_required: rule.gst_review_required,
        warning_codes: rule.warning_codes,
        explanation: category_remapped ? "#{rule.explanation} Used the matching category name from the reference workbook: #{category}." : rule.explanation,
        reference_snapshot: {},
        metadata: {
          "rule_id" => rule.rule_id,
          "rule_default_category" => rule.category,
          "category_vocabulary_remapped" => category_remapped
        }
      )
    end

    def category_for_rule(rule, category_vocabulary)
      patterns = CATEGORY_VOCABULARY_PATTERNS[rule.rule_id]
      return rule.category if patterns.blank?

      matches = category_vocabulary.keys.select do |category|
        patterns.any? { |pattern| category.match?(pattern) }
      end
      grouped = matches.group_by { |category| normalized_category(category) }
      return rule.category unless grouped.one?

      grouped.values.first.max_by { |category| [ category_vocabulary.fetch(category), category ] }
    end

    def normalized_zero(value)
      return if value.nil?

      value.to_d.zero? ? BigDecimal("0") : value.to_d
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
      warnings << "gst_unclassified" if gst_amount.nil? && gst_source == "unmatched"
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
