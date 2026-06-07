require "test_helper"

class BasMatchTest < ActiveSupport::TestCase
  test "validates match type status and confidence" do
    match = BasMatch.new(
      bas_job: bas_job,
      match_type: "invoice_to_bank_transaction",
      status: "proposed",
      confidence: BigDecimal("80.0")
    )

    assert match.valid?, match.errors.full_messages.to_sentence

    match.match_type = "unsupported"
    match.status = "closed"
    match.confidence = BigDecimal("101.0")

    assert_not match.valid?
    assert_equal :inclusion, match.errors.details[:match_type].first.fetch(:error)
    assert_equal :inclusion, match.errors.details[:status].first.fetch(:error)
    assert_equal :less_than_or_equal_to, match.errors.details[:confidence].first.fetch(:error)
  end

  test "match item validates polymorphic matchable and same job" do
    job = bas_job
    other_job = bas_job(legal_name: "Other Synthetic Pty Ltd")
    match = BasMatch.create!(bas_job: job, match_type: "manual")
    invoice = BasInvoice.create!(bas_job: other_job, total_amount: BigDecimal("110.00"))
    item = BasMatchItem.new(bas_match: match, matchable: invoice, amount: invoice.total_amount)

    assert_not item.valid?
    assert_includes item.errors[:matchable], "must belong to the same BAS job"

    invoice.update!(bas_job: job)
    assert item.valid?, item.errors.full_messages.to_sentence
  end

  test "bas query source and dedupe fields enforce job scoped uniqueness" do
    job = bas_job
    first = job.queries.create!(
      title: "Synthetic generated query",
      query_type: "unmatched_invoice",
      dedupe_key: "synthetic:1",
      source_type: "BasInvoice",
      source_id: 1,
      generated_by_rule: "test_rule",
      auto_generated: true
    )
    duplicate = job.queries.build(title: "Duplicate", query_type: "unmatched_invoice", dedupe_key: first.dedupe_key)

    assert_not duplicate.valid?
    assert_equal :taken, duplicate.errors.details[:dedupe_key].first.fetch(:error)
  end

  private

  def bas_job(legal_name: "Synthetic Match Client Pty Ltd")
    BasJob.create!(
      bas_client: BasClient.create!(legal_name: legal_name),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31)
    )
  end
end
