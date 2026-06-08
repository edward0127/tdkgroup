require "test_helper"

class BasQueriesSourceResolutionSyncTest < ActiveSupport::TestCase
  test "ignoring a bank transaction auto resolves related generated open query" do
    transaction = bank_transaction
    query = generated_query_for(transaction, query_type: "unmatched_bank_transaction")
    transaction.update!(status: "ignored")

    assert_difference -> { BasAuditEvent.where(event_type: "bas_query_auto_resolved").count }, 1 do
      assert_equal 1, sync(transaction)
    end

    assert_equal "resolved", query.reload.status
    assert_equal BasQueries::SourceResolutionSync::RESOLUTION_NOTE, query.resolution_notes
    assert_equal "bas-query-sync-admin", query.updated_by
  end

  test "ignoring an invoice auto resolves related generated open query" do
    invoice = invoice_record
    query = generated_query_for(invoice, query_type: "unmatched_invoice")
    invoice.update!(status: "ignored")

    assert_equal 1, sync(invoice)

    assert_equal "resolved", query.reload.status
    assert_equal BasQueries::SourceResolutionSync::RESOLUTION_NOTE, query.resolution_notes
  end

  test "accepted match auto resolves related generated open query" do
    invoice = invoice_record
    query = generated_query_for(invoice, query_type: "unmatched_invoice")
    match = BasMatch.create!(
      bas_job: bas_job,
      match_type: "manual",
      status: "accepted",
      accepted_at: Time.current,
      accepted_by: "bas-query-sync-admin"
    )
    match.items.create!(matchable: invoice, amount: invoice.total_amount)

    assert_equal 1, sync(invoice)

    assert_equal "resolved", query.reload.status
  end

  test "BAS-excluded source auto resolves related generated open query" do
    invoice = invoice_record(gst_code: "bas_excluded")
    query = generated_query_for(invoice, query_type: "unmatched_invoice")

    assert_equal 1, sync(invoice)

    assert_equal "resolved", query.reload.status
    assert_equal "BAS-excluded", query.source_status_label
  end

  test "already resolved queries are not changed" do
    transaction = bank_transaction(status: "ignored")
    query = generated_query_for(
      transaction,
      query_type: "unmatched_bank_transaction",
      status: "resolved",
      resolution_notes: "Already handled."
    )

    assert_no_difference -> { BasAuditEvent.where(event_type: "bas_query_auto_resolved").count } do
      assert_equal 0, sync(transaction)
    end

    assert_equal "Already handled.", query.reload.resolution_notes
  end

  test "manual or staff-noted queries are not overwritten" do
    transaction = bank_transaction(status: "ignored")
    manual_query = generated_query_for(
      transaction,
      query_type: "unmatched_bank_transaction",
      auto_generated: false
    )
    noted_query = generated_query_for(
      transaction,
      query_type: "missing_receipt",
      resolution_notes: "Staff is already following up."
    )

    assert_equal 0, sync(transaction)

    assert_equal "open", manual_query.reload.status
    assert_equal "open", noted_query.reload.status
    assert_equal "Staff is already following up.", noted_query.resolution_notes
  end

  private

  def sync(source)
    BasQueries::SourceResolutionSync.new(source: source, actor_username: "bas-query-sync-admin").call
  end

  def bas_job
    @bas_job ||= BasJob.create!(
      bas_client: BasClient.create!(legal_name: "Generic Query Sync Client Pty Ltd"),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31)
    )
  end

  def bank_transaction(attributes = {})
    BasBankTransaction.create!({
      bas_job: bas_job,
      transaction_date: Date.new(2026, 3, 12),
      description: "Generic supplier payment",
      amount: BigDecimal("77.00"),
      status: "imported"
    }.merge(attributes))
  end

  def invoice_record(attributes = {})
    BasInvoice.create!({
      bas_job: bas_job,
      invoice_number: "INV-SYNC",
      issue_date: Date.new(2026, 3, 13),
      party_name: "Generic supplier",
      total_amount: BigDecimal("88.00"),
      gst_amount: BigDecimal("8.00"),
      status: "imported"
    }.merge(attributes))
  end

  def generated_query_for(source, attributes = {})
    BasQuery.create!({
      bas_job: bas_job,
      title: "Generated source query",
      query_type: "other",
      status: "open",
      source_type: source.class.name,
      source_id: source.id,
      dedupe_key: "sync-test:#{SecureRandom.hex(8)}",
      generated_by_rule: "sync_test",
      auto_generated: true,
      created_by: "test",
      updated_by: "test"
    }.merge(attributes))
  end
end
