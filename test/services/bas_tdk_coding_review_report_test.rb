require "test_helper"

class BasTdkCodingReviewReportTest < ActiveSupport::TestCase
  Coding = Struct.new(
    :id,
    :category_review_required,
    :gst_review_required,
    :category_source,
    :gst_source,
    :suggested_category,
    :suggested_gst_amount,
    :category_confidence,
    :gst_confidence,
    :warning_codes,
    :metadata,
    keyword_init: true
  ) do
    def review_required?
      category_review_required? || gst_review_required?
    end

    def category_review_required?
      category_review_required == true
    end

    def gst_review_required?
      gst_review_required == true
    end
  end

  test "builds exclusive row reason groups and independent field counts" do
    codings = [
      coding(id: 1, category_source: "unmatched", gst_source: "unmatched"),
      coding(
        id: 2,
        category_source: "previous_quarter_fuzzy",
        gst_source: "previous_quarter_fuzzy",
        suggested_category: "Sales",
        suggested_gst_amount: 9.09,
        category_confidence: 94,
        gst_confidence: 94,
        warning_codes: [ "historical_merchant_match" ],
        metadata: { "match_type" => "merchant" }
      ),
      coding(
        id: 3,
        category_source: "rule",
        gst_source: "rule",
        suggested_category: "Packaging",
        suggested_gst_amount: 9.18,
        warning_codes: [ "rule_suggestion_requires_review", "tax_invoice_required" ],
        metadata: { "rule_id" => "packaging" }
      ),
      coding(
        id: 4,
        category_source: "unmatched",
        gst_source: "unmatched",
        warning_codes: [ "historical_category_suppressed", "mixed_or_unsafe_gst" ],
        metadata: {
          "category_suppressed_by_rule_id" => "uncertain_retailer",
          "gst_suppressed_by_rule_id" => "uncertain_retailer"
        }
      ),
      coding(
        id: 5,
        category_review_required: false,
        category_source: "previous_quarter_exact",
        gst_source: "unmatched",
        suggested_category: "Purchase",
        warning_codes: [ "historical_gst_conflict", "gst_unclassified" ],
        metadata: { "match_type" => "exact", "gst_consensus_status" => "conflict" }
      ),
      coding(
        id: 6,
        gst_review_required: false,
        category_source: "previous_quarter_exact",
        gst_source: "previous_quarter_exact",
        suggested_category: "Sales",
        warning_codes: [ "historical_category_coverage_incomplete" ],
        metadata: { "match_type" => "exact" }
      ),
      coding(
        id: 7,
        category_review_required: false,
        gst_review_required: false,
        category_source: "previous_quarter_exact",
        gst_source: "previous_quarter_exact",
        suggested_category: "Fuel",
        suggested_gst_amount: 9.27
      )
    ]

    report = BasTdk::CodingReviewReport.new(codings: codings).call

    assert_equal 6, report.fetch(:total_review_rows)
    assert_equal({ category: 5, gst: 5 }, report.fetch(:field_counts))
    assert_equal({ category_only: 1, gst_only: 1, both: 4 }, report.fetch(:field_combinations))

    group_counts = report.fetch(:reason_groups).to_h { |group| [ group.fetch(:key), group.fetch(:count) ] }
    assert_equal 6, group_counts.values.sum
    assert_equal 1, group_counts.fetch(:unclassified)
    assert_equal 2, group_counts.fetch(:prior_quarter_non_exact)
    assert_equal 1, group_counts.fetch(:rule_derived)
    assert_equal 1, group_counts.fetch(:uncertain_or_blank)
    assert_equal 1, group_counts.fetch(:historical_gst_issue)
    assert_not_includes group_counts, :other

    assert_equal :unclassified, report.dig(:row_reason_by_coding_id, 1, :key)
    assert_equal :prior_quarter_non_exact, report.dig(:row_reason_by_coding_id, 2, :key)
    assert_equal :rule_derived, report.dig(:row_reason_by_coding_id, 3, :key)
    assert_equal :uncertain_or_blank, report.dig(:row_reason_by_coding_id, 4, :key)
    assert_equal :historical_gst_issue, report.dig(:row_reason_by_coding_id, 5, :key)
    assert_equal :prior_quarter_non_exact, report.dig(:row_reason_by_coding_id, 6, :key)
    assert_nil report.dig(:row_reason_by_coding_id, 7)
  end

  test "provides a specific reason for each highlighted field" do
    codings = [
      coding(
        id: 1,
        category_source: "previous_quarter_fuzzy",
        gst_source: "unmatched",
        suggested_category: "Repairs",
        category_confidence: 88,
        warning_codes: [ "historical_merchant_match", "historical_gst_missing" ],
        metadata: { "match_type" => "merchant", "gst_consensus_status" => "incomplete" }
      ),
      coding(
        id: 2,
        category_source: "rule",
        gst_source: "rule",
        suggested_category: "Staff amenities",
        suggested_gst_amount: 7.73,
        warning_codes: [ "rule_suggestion_requires_review", "tax_invoice_required" ],
        metadata: { "rule_id" => "staff_amenities" }
      )
    ]

    report = BasTdk::CodingReviewReport.new(codings: codings).call
    merchant_reasons = report.dig(:field_reasons_by_coding_id, 1)
    rule_reasons = report.dig(:field_reasons_by_coding_id, 2)

    assert_equal :prior_quarter_non_exact, merchant_reasons.dig(:category, :key)
    assert_match(/merchant appeared in the prior quarter/i, merchant_reasons.dig(:category, :detail))
    assert_equal :historical_gst_issue, merchant_reasons.dig(:gst, :key)
    assert_match(/did not contain enough consistent GST/i, merchant_reasons.dig(:gst, :detail))
    assert_equal :rule_derived, rule_reasons.dig(:category, :key)
    assert_match(/business-use percentage/i, rule_reasons.dig(:gst, :detail))
  end

  test "returns a complete zero report for an empty run" do
    report = BasTdk::CodingReviewReport.new(codings: []).call

    assert_equal 0, report.fetch(:total_review_rows)
    assert_equal({ category: 0, gst: 0 }, report.fetch(:field_counts))
    assert_equal({ category_only: 0, gst_only: 0, both: 0 }, report.fetch(:field_combinations))
    assert_empty report.fetch(:reason_groups)
    assert_empty report.fetch(:row_reason_by_coding_id)
    assert_empty report.fetch(:field_reasons_by_coding_id)
  end

  test "keeps production unmatched and conflicting evidence out of generic rule groups" do
    unmatched = coding(
      id: 1,
      category_source: "unmatched",
      gst_source: "unmatched",
      warning_codes: [ "category_unclassified", "gst_unclassified" ],
      metadata: { "rule_id" => "unmatched" }
    )
    conflict = coding(
      id: 2,
      category_source: "unmatched",
      gst_source: "unmatched",
      warning_codes: [ "historical_evidence_conflict" ],
      metadata: { "match_type" => "evidence_conflict" }
    )

    report = BasTdk::CodingReviewReport.new(codings: [ unmatched, conflict ]).call

    assert_equal :unclassified, report.dig(:row_reason_by_coding_id, 1, :key)
    assert_equal :historical_gst_issue, report.dig(:row_reason_by_coding_id, 2, :key)
    assert_match(/prior-quarter merchant or bank-template evidence/i, report.dig(:field_reasons_by_coding_id, 2, :category, :detail))
    assert_equal({ unclassified: 1, historical_gst_issue: 1 }, report.fetch(:reason_groups).to_h { |group| [ group.fetch(:key), group.fetch(:count) ] })
  end

  test "does not copy a Category suppression reason onto GST without GST evidence" do
    coding = coding(
      id: 1,
      category_source: "unmatched",
      gst_source: "unmatched",
      warning_codes: [ "historical_category_suppressed", "gst_unclassified" ],
      metadata: { "category_suppressed_by_rule_id" => "uncertain_retailer" }
    )

    report = BasTdk::CodingReviewReport.new(codings: [ coding ]).call

    assert_equal :uncertain_or_blank, report.dig(:field_reasons_by_coding_id, 1, :category, :key)
    assert_equal :unclassified, report.dig(:field_reasons_by_coding_id, 1, :gst, :key)
  end

  test "explains a paired validation offset without implying an invoice rule" do
    coding = coding(
      id: 1,
      category_source: "rule",
      gst_source: "unmatched",
      suggested_category: "Validation transfers",
      warning_codes: [ "rule_suggestion_requires_review", "paired_validation_offset" ],
      metadata: { "rule_id" => "paired_validation_offset" }
    )

    report = BasTdk::CodingReviewReport.new(codings: [ coding ]).call

    assert_equal :rule_derived, report.dig(:field_reasons_by_coding_id, 1, :gst, :key)
    assert_match(/equal-and-opposite validation pair/i, report.dig(:field_reasons_by_coding_id, 1, :gst, :detail))
  end

  test "uses a rule as the row reason when a rule Category has uncertain GST" do
    mixed_retailer = coding(
      id: 1,
      category_source: "rule",
      gst_source: "unmatched",
      suggested_category: "General expenses",
      warning_codes: [ "rule_suggestion_requires_review", "mixed_or_unsafe_gst", "mixed_retailer" ],
      metadata: { "rule_id" => "mixed_retailer" }
    )

    report = BasTdk::CodingReviewReport.new(codings: [ mixed_retailer ]).call

    assert_equal :rule_derived, report.dig(:field_reasons_by_coding_id, 1, :category, :key)
    assert_equal :uncertain_or_blank, report.dig(:field_reasons_by_coding_id, 1, :gst, :key)
    assert_equal :rule_derived, report.dig(:row_reason_by_coding_id, 1, :key)
  end

  test "explains a no-GST rule without asking for an invoice estimate" do
    ato = coding(
      id: 1,
      category_source: "rule",
      gst_source: "rule",
      suggested_category: "Tax payments",
      suggested_gst_amount: 0,
      warning_codes: [ "rule_suggestion_requires_review", "ato_payment" ],
      metadata: { "rule_id" => "ato_payment" }
    )

    report = BasTdk::CodingReviewReport.new(codings: [ ato ]).call
    detail = report.dig(:field_reasons_by_coding_id, 1, :gst, :detail)

    assert_match(/set GST to 0/i, detail)
    assert_match(/no claimable GST/i, detail)
    assert_no_match(/tax invoice/i, detail)
  end

  test "excludes accepted rows and explains manually edited rows that are reopened" do
    accepted = coding(
      id: 1,
      category_review_required: false,
      gst_review_required: false,
      category_source: "manual",
      gst_source: "manual",
      suggested_category: "Repairs",
      suggested_gst_amount: 9.09,
      warning_codes: [ "category_unclassified", "gst_unclassified" ]
    )
    reopened = coding(
      id: 2,
      category_source: "manual",
      gst_source: "manual",
      suggested_category: "Repairs",
      suggested_gst_amount: 9.09,
      warning_codes: [ "category_unclassified", "gst_unclassified", "historical_gst_conflict" ],
      metadata: { "match_type" => "evidence_conflict" }
    )

    report = BasTdk::CodingReviewReport.new(codings: [ accepted, reopened ]).call

    assert_equal 1, report.fetch(:total_review_rows)
    assert_nil report.dig(:field_reasons_by_coding_id, 1)
    assert_equal :other, report.dig(:row_reason_by_coding_id, 2, :key)
    assert_match(/entered manually/i, report.dig(:field_reasons_by_coding_id, 2, :category, :detail))
    assert_match(/Reviewed check was later cleared/i, report.dig(:field_reasons_by_coding_id, 2, :gst, :detail))
  end

  private

  def coding(attributes)
    Coding.new({
      category_review_required: true,
      gst_review_required: true,
      category_source: "unmatched",
      gst_source: "unmatched",
      suggested_category: nil,
      suggested_gst_amount: nil,
      category_confidence: 0,
      gst_confidence: 0,
      warning_codes: [],
      metadata: {}
    }.merge(attributes))
  end
end
