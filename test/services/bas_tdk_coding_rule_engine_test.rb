require "test_helper"

class BasTdkCodingRuleEngineTest < ActiveSupport::TestCase
  test "applies explicit deterministic no-GST rules but still requires review" do
    {
      "ATO BAS payment" => [ "Tax payments", "bas_excluded", "ato_payment" ],
      "Employee wages batch" => [ "Wages & salaries", "bas_excluded", "employee_wages" ],
      "Super clearing house" => [ "Superannuation", "bas_excluded", "superannuation" ],
      "Monthly account fee" => [ "Bank fees", "input_taxed", "bank_fee" ],
      "Account fee" => [ "Bank fees", "input_taxed", "bank_fee" ],
      "Internal transfer between accounts" => [ "Transfers", "bas_excluded", "explicit_transfer" ]
    }.each do |description, (category, treatment, rule_id)|
      suggestion = rule(description, -100)
      assert_equal category, suggestion.category
      assert_equal BigDecimal("0"), suggestion.gst_amount
      assert_equal treatment, suggestion.gst_treatment
      assert_equal rule_id, suggestion.rule_id
      assert suggestion.category_review_required
      assert suggestion.gst_review_required
      assert_includes suggestion.warning_codes, "rule_suggestion_requires_review"
    end
  end

  test "uses signed one-eleventh only for probable taxable outgoing expenses" do
    debit = rule("Adobe software subscription", -121)
    credit = rule("Adobe software subscription refund", 121)

    assert_equal "Software & subscriptions", debit.category
    assert_equal BigDecimal("-11"), debit.gst_amount
    assert_equal "taxable", debit.gst_treatment
    assert_includes debit.warning_codes, "tax_invoice_required"
    assert_includes debit.explanation, "business-use percentage"
    assert_equal "unmatched", credit.rule_id
    assert_nil credit.gst_amount
  end

  test "leaves GST blank for mixed or unsafe suppliers" do
    suggestion = rule("Woolworths supermarket", -110)

    assert_equal "General expenses", suggestion.category
    assert_nil suggestion.gst_amount
    assert_equal "needs_review", suggestion.gst_treatment
    assert_includes suggestion.warning_codes, "mixed_or_unsafe_gst"
  end

  test "does not infer no GST for generic transaction fees or one-eleventh GST for water" do
    transaction_fee = rule("Marketplace transaction fee", -11)
    water = rule("Quarterly water usage bill", -110)

    assert_equal "unmatched", transaction_fee.rule_id
    assert_nil transaction_fee.gst_amount
    assert_equal "water_supply", water.rule_id
    assert_equal "Utilities", water.category
    assert_nil water.gst_amount
    assert water.gst_review_required
  end

  test "unmatched transactions remain blank and warned" do
    suggestion = rule("Unfamiliar counterparty", -42)

    assert_nil suggestion.category
    assert_nil suggestion.gst_amount
    assert_equal "unmatched", suggestion.rule_id
    assert_equal [ "category_unclassified", "gst_unclassified" ], suggestion.warning_codes
  end

  private

  def rule(description, amount)
    BasTdk::CodingRuleEngine.new(description: description, amount: amount).call
  end
end
