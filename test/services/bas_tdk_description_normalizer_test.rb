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
end
