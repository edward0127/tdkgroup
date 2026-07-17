require "test_helper"

class BasTdkDescriptionNormalizerTest < ActiveSupport::TestCase
  test "normalizes recurring merchant descriptions while removing bank noise" do
    first = BasTdk::DescriptionNormalizer.call("EFTPOS DEBIT 30/03/2026 OFFICEWORKS 001234 REF 99887766")
    second = BasTdk::DescriptionNormalizer.call("Card purchase OFFICEWORKS 29/06/2026 receipt 11223344")

    assert_equal "officeworks", first
    assert_equal "officeworks", second
    assert_operator BasTdk::DescriptionNormalizer.similarity(first, second), :>=, 0.94
  end

  test "does not match descriptions made only from generic banking words and references" do
    refute BasTdk::DescriptionNormalizer.matchable?("Transfer to account 9988776655")
    refute BasTdk::DescriptionNormalizer.matchable?("EFTPOS debit card payment")
  end

  test "keeps meaningful merchant words and rejects unrelated descriptions" do
    assert BasTdk::DescriptionNormalizer.matchable?("Adobe Creative Cloud subscription")
    assert_operator BasTdk::DescriptionNormalizer.similarity("Adobe Creative Cloud", "Adobe Creative Cloud AU"), :>=, 0.94
    assert_operator BasTdk::DescriptionNormalizer.similarity("Adobe Creative Cloud", "Wilson Parking"), :<, 0.94
  end

  test "does not treat refrigeration words as reference labels" do
    misspelled = BasTdk::DescriptionNormalizer.call(
      "Transfer to other Bank NetBank Frecks refgration"
    )

    assert_includes misspelled, "frecks refgration"
    assert_equal "refrigeration repairs", BasTdk::DescriptionNormalizer.call(
      "Refrigeration repairs REF 12345678"
    )
  end

  test "removes channel names and textual transaction dates" do
    first = BasTdk::DescriptionNormalizer.call("NetBank EFTPOS 30 JUN OFFICEWORKS")
    second = BasTdk::DescriptionNormalizer.call("EFTPOS JUN 30, 2026 OFFICEWORKS")

    assert_equal "officeworks", first
    assert_equal "officeworks", second
  end

  test "folds explicit DoorDash and Adyen provider ids" do
    first_doordash = BasTdk::DescriptionNormalizer.call(
      "Direct Credit 507141 DoorDashMilduraN DoorDashM_UmSfgSMV"
    )
    second_doordash = BasTdk::DescriptionNormalizer.call(
      "Direct Credit 507141 DoorDashMilduraN DoorDashM_UiqFomoy"
    )
    first_adyen = BasTdk::DescriptionNormalizer.call(
      "Fast Transfer From ADYEN AUSTRALIA EXT BAL SWEEP SWPE42WS322322235PKGHTM XCH265PLG8ZQP63"
    )
    second_adyen = BasTdk::DescriptionNormalizer.call(
      "Fast Transfer From ADYEN AUSTRALIA EXT BAL SWEEP SWPE429T522322235PJGXF8 XCH265PKGPKS9HK"
    )

    assert_equal "doordashmilduran doordash", first_doordash
    assert_equal first_doordash, second_doordash
    assert_equal "fast adyen ext bal sweep", first_adyen
    assert_equal first_adyen, second_adyen
  end

  test "keeps code-like merchant text without the matching provider" do
    normalized = BasTdk::DescriptionNormalizer.call("SWPE42ABCDEF XCH265ABCDEF Merchant")
    far_from_provider = BasTdk::DescriptionNormalizer.call(
      "ADYEN #{Array.new(20, "merchant").join(" ")} SWPE42ABCDEF"
    )

    assert_includes normalized, "swpe 42 abcdef"
    assert_includes normalized, "xch 265 abcdef"
    assert_includes far_from_provider, "swpe 42 abcdef"
  end
end
