require "test_helper"

class AdminBasWorkflowHelperTest < ActiveSupport::TestCase
  Coding = Struct.new(
    :id,
    :warning_codes,
    :metadata,
    :category_source,
    :gst_source,
    :category_review_required,
    :gst_review_required,
    keyword_init: true
  ) do
    def category_review_required?
      category_review_required
    end

    def gst_review_required?
      gst_review_required
    end
  end

  setup do
    @helper = Object.new.extend(Admin::Bas::WorkflowHelper)
  end

  test "review report helpers accept string keys and expose field-specific backend reasons" do
    @helper.instance_variable_set(:@tdk_coding_review_report, {
      "total_review_rows" => 45,
      "field_counts" => { "category" => 45, "gst" => 43 },
      "field_combinations" => { "category_only" => 2, "gst_only" => 0, "both" => 43 },
      "reason_groups" => [
        { "key" => "prior_quarter_non_exact", "title" => "Non-exact history", "description" => "History needs confirmation.", "count" => 18 }
      ],
      "field_reasons_by_coding_id" => {
        "42" => {
          "category" => { "detail" => "Only one similar prior-quarter example supports this Category." }
        }
      }
    })
    coding = coding(id: 42)

    assert_equal 45, @helper.tdk_coding_review_report_value(:total_review_rows)
    assert_equal 45, @helper.tdk_coding_review_field_count(:category)
    assert_equal 43, @helper.tdk_coding_review_combination_count(:both)
    assert_equal "Only one similar prior-quarter example supports this Category.", @helper.tdk_coding_field_review_reason(coding, :category)
  end

  test "review reason fallback explains unmatched GST and non-exact Category in plain English" do
    category_coding = coding(
      warning_codes: [ "historical_merchant_match" ],
      metadata: { "match_type" => "merchant" },
      category_source: "previous_quarter_fuzzy"
    )
    gst_coding = coding(
      warning_codes: [ "gst_unclassified" ],
      gst_source: "unmatched"
    )

    assert_equal "The merchant matched prior-quarter history, but this transaction description is not an exact match.",
      @helper.tdk_coding_field_review_reason(category_coding, :category)
    assert_equal "No reliable prior-quarter GST treatment or conservative rule could determine GST.",
      @helper.tdk_coding_field_review_reason(gst_coding, :gst)
  end

  test "next action distinguishes Category-only GST-only and combined review" do
    assert_match(/Confirm the Category/, @helper.tdk_coding_review_next_action(coding(category_review_required: true, gst_review_required: false)))
    assert_match(/tax invoice/, @helper.tdk_coding_review_next_action(coding(category_review_required: false, gst_review_required: true)))
    assert_match(/Edit either value/, @helper.tdk_coding_review_next_action(coding(category_review_required: true, gst_review_required: true)))
  end

  private

  def coding(attributes = {})
    Coding.new({
      id: 1,
      warning_codes: [],
      metadata: {},
      category_source: "rule",
      gst_source: "rule",
      category_review_required: true,
      gst_review_required: true
    }.merge(attributes))
  end
end
