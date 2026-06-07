require "test_helper"

class BasQueriesEmailDraftBuilderTest < ActiveSupport::TestCase
  test "builds subject with client name and BAS period" do
    job = bas_job

    result = build(job)

    assert_includes result.subject, "Synthetic Draft Client Pty Ltd"
    assert_includes result.subject, job.period_label
  end

  test "builds body from open and waiting queries" do
    job = bas_job
    open_query = query(job, title: "Missing fuel receipt", details: "Fuel receipt for January.")
    waiting_query = query(job, title: "Waiting bank explanation", query_type: "unmatched_bank_transaction", status: "waiting_for_client")

    result = build(job)

    assert_includes result.body, "We are preparing your BAS for #{job.period_label}"
    assert_includes result.body, open_query.title
    assert_includes result.body, waiting_query.title
    assert_equal [ open_query.id, waiting_query.id ].sort, result.queries.map(&:id).sort
  end

  test "groups missing invoices and receipts together" do
    job = bas_job
    query(job, title: "Missing supplier invoice", query_type: "missing_invoice")
    query(job, title: "Missing payment receipt", query_type: "missing_receipt")
    query(job, title: "Missing support", query_type: "supporting_document_missing")

    result = build(job)

    assert_equal 1, result.groups.count { |group| group.title == "Missing invoices or receipts" }
    assert_includes result.body, "Please provide the invoice or receipt for the following transaction."
  end

  test "groups unmatched bank transactions with safe related fields" do
    job = bas_job
    transaction = BasBankTransaction.create!(
      bas_job: job,
      transaction_date: Date.new(2026, 1, 12),
      description: "Synthetic bank payment",
      amount: BigDecimal("220.00"),
      status: "imported"
    )
    query(job, title: "Confirm bank payment", query_type: "unmatched_bank_transaction", source_type: "BasBankTransaction", source_id: transaction.id)

    result = build(job)

    assert_includes result.body, "Bank transactions to confirm"
    assert_includes result.body, "Date: 2026-01-12"
    assert_includes result.body, "Description: Synthetic bank payment"
    assert_includes result.body, "Amount: $220.00"
  end

  test "groups GST treatment queries" do
    job = bas_job
    query(job, title: "Confirm GST on invoice", query_type: "gst_treatment_unclear")
    query(job, title: "Review GST code", query_type: "unreviewed_gst_code")

    result = build(job)

    assert_equal 1, result.groups.count { |group| group.title == "GST treatment to confirm" }
    assert_includes result.body, "Please confirm whether GST applies to the following item"
  end

  test "excludes resolved and dismissed queries" do
    job = bas_job
    open_query = query(job, title: "Open client question")
    query(job, title: "Resolved client question", status: "resolved", resolution_notes: "Resolved.")
    query(job, title: "Dismissed client question", status: "dismissed", resolution_notes: "Dismissed.")

    result = build(job)

    assert_equal [ open_query.id ], result.queries.map(&:id)
    assert_includes result.body, "Open client question"
    assert_not_includes result.body, "Resolved client question"
    assert_not_includes result.body, "Dismissed client question"
  end

  test "does not include internal notes or audit metadata" do
    job = bas_job(internal_notes: "PRIVATE INTERNAL NOTES")
    query(job, title: "Client-safe query", details: "Please confirm this item.")
    BasAuditEvent.create!(
      bas_job: job,
      event_type: "synthetic_internal_event",
      actor_username: "admin",
      metadata: { raw_prompt: "SECRET RAW PROMPT", api_key: "sk-secret" }
    )

    result = build(job)

    assert_not_includes result.body, "PRIVATE INTERNAL NOTES"
    assert_not_includes result.body, "SECRET RAW PROMPT"
    assert_not_includes result.body, "sk-secret"
    assert_not_includes result.body, "raw_prompt"
  end

  test "handles no client email" do
    job = bas_job(contact_email: nil)
    query(job, title: "Missing receipt")

    result = build(job)

    assert_nil result.recipient_email
    assert_includes result.body, "Hi Synthetic Contact,"
    assert_includes result.subject, job.bas_client.display_name
  end

  test "handles no open queries" do
    job = bas_job
    query(job, title: "Resolved item", status: "resolved", resolution_notes: "Resolved.")

    result = build(job)

    assert_empty result.queries
    assert_empty result.groups
    assert_includes result.body, "There are currently no open client queries for this BAS job."
  end

  private

  def build(job)
    BasQueries::EmailDraftBuilder.new(bas_job: job).call
  end

  def bas_job(attributes = {})
    contact_email = attributes.delete(:contact_email) { "draft-client@example.test" }
    client = BasClient.create!(
      legal_name: "Synthetic Draft Client Pty Ltd",
      contact_name: "Synthetic Contact",
      contact_email: contact_email,
      default_gst_basis: "accrual",
      default_reporting_method: "simpler_bas"
    )
    BasJob.create!({
      bas_client: client,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      gst_basis: "accrual",
      reporting_method: "simpler_bas"
    }.merge(attributes))
  end

  def query(job, attributes = {})
    job.queries.create!({
      title: "Synthetic client query",
      query_type: "missing_receipt",
      status: "open",
      details: "Synthetic client-safe details.",
      created_by: "test-admin",
      updated_by: "test-admin"
    }.merge(attributes))
  end
end
