require "test_helper"

class BasQueryTest < ActiveSupport::TestCase
  test "validates required and allowlisted fields" do
    query = BasQuery.new(bas_job: bas_job, title: "Missing receipt", query_type: "missing_receipt")
    assert query.valid?, query.errors.full_messages.to_sentence

    query.title = ""
    query.status = "closed"
    query.query_type = "unknown"

    assert_not query.valid?
    assert_equal :blank, query.errors.details[:title].first.fetch(:error)
    assert_equal :inclusion, query.errors.details[:status].first.fetch(:error)
    assert_equal :inclusion, query.errors.details[:query_type].first.fetch(:error)
  end

  test "requires resolution notes and timestamps resolved queries" do
    query = BasQuery.new(bas_job: bas_job, title: "GST treatment unclear", status: "resolved")

    assert_not query.valid?
    assert_includes query.errors[:resolution_notes], "must be provided when resolving or dismissing a query"

    query.resolution_notes = "Synthetic resolution notes."
    assert query.save, query.errors.full_messages.to_sentence
    assert query.resolved_at.present?
  end

  test "display title includes bank transaction source and amount" do
    transaction = BasBankTransaction.create!(
      bas_job: bas_job,
      transaction_date: Date.new(2026, 3, 12),
      description: "Generic supplier card purchase",
      amount: BigDecimal("77.00"),
      status: "imported"
    )
    query = BasQuery.create!(
      bas_job: bas_job,
      title: "Unmatched bank transaction",
      query_type: "unmatched_bank_transaction",
      source_type: "BasBankTransaction",
      source_id: transaction.id,
      auto_generated: true
    )

    assert_equal "Unmatched bank transaction  Generic supplier card purchase  $77.00", query.display_title
    assert_equal "Generic supplier card purchase  2026-03-12", query.source_summary
    assert_equal BigDecimal("77.00"), query.source_amount
  end

  test "display title includes invoice source and amount" do
    invoice = BasInvoice.create!(
      bas_job: bas_job,
      invoice_number: "INV-123",
      issue_date: Date.new(2026, 3, 15),
      party_name: "Generic advertising provider",
      total_amount: BigDecimal("132.00"),
      gst_amount: BigDecimal("12.00"),
      status: "imported"
    )
    query = BasQuery.create!(
      bas_job: bas_job,
      title: "Unmatched invoice",
      query_type: "unmatched_invoice",
      source_type: "BasInvoice",
      source_id: invoice.id,
      auto_generated: true
    )

    assert_equal "Unmatched invoice  Generic advertising provider  $132.00", query.display_title
    assert_equal "Generic advertising provider  INV-123  2026-03-15", query.source_summary
  end

  test "display title falls back to stored title when source is missing" do
    query = BasQuery.create!(
      bas_job: bas_job,
      title: "Stored fallback query",
      query_type: "other",
      source_type: "BasBankTransaction",
      source_id: 99_999
    )

    assert_equal "Stored fallback query", query.display_title
    assert_nil query.source_summary
  end

  private

  def bas_job
    @bas_job ||= BasJob.create!(
      bas_client: BasClient.create!(legal_name: "Synthetic Client Pty Ltd"),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31)
    )
  end
end
