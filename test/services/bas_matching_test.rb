require "test_helper"

class BasMatchingTest < ActiveSupport::TestCase
  test "confidence scorer returns confidence and explanation" do
    job = bas_job
    invoice = invoice(job, party_name: "Synthetic Customer", total_amount: "110.00", payment_method: "bank")
    bank = bank_transaction(job, description: "Payment Synthetic Customer", amount: "110.00")

    result = BasMatching::ConfidenceScorer.score(invoice: invoice, payment_record: bank)

    assert_operator result.confidence, :>=, 70
    assert_match "amount matches", result.explanation
  end

  test "exact invoice to bank matching creates proposed match" do
    job = bas_job
    invoice(job, invoice_number: "INV-001", party_name: "Synthetic Customer", total_amount: "110.00", payment_method: "bank")
    bank_transaction(job, description: "Synthetic Customer payment", amount: "-110.00")

    assert_difference "BasMatch.count", 1 do
      BasMatching::Matcher.new(bas_job: job, actor_username: "phase3").call
    end

    match = BasMatch.last
    assert_equal "invoice_to_bank_transaction", match.match_type
    assert_equal "proposed", match.status
    assert_equal 2, match.items.count
    assert_equal "matching", job.reload.status
  end

  test "many invoices to one bank transaction matching creates proposed match" do
    job = bas_job
    invoice(job, invoice_number: "INV-001", party_name: "Synthetic Customer", total_amount: "50.00")
    invoice(job, invoice_number: "INV-002", party_name: "Synthetic Customer", total_amount: "60.00")
    bank_transaction(job, description: "Synthetic Customer batch payment", amount: "110.00")

    BasMatching::Matcher.new(bas_job: job, actor_username: "phase3").call

    match = BasMatch.find_by!(match_type: "invoices_to_bank_transaction")
    assert_equal 3, match.items.count
    assert_equal BigDecimal("110.00"), match.matched_amount
  end

  test "cross party grouped purchase invoices can match one bank payment" do
    job = bas_job
    first_invoice = invoice(
      job,
      direction: "purchase",
      invoice_number: "GEN-001",
      party_name: "Generic Alpha",
      total_amount: "40.00",
      paid_date: Date.new(2026, 1, 4)
    )
    second_invoice = invoice(
      job,
      direction: "purchase",
      invoice_number: "GEN-002",
      party_name: "Generic Beta",
      total_amount: "60.00",
      paid_date: Date.new(2026, 1, 4)
    )
    payment = bank_transaction(
      job,
      transaction_date: Date.new(2026, 1, 4),
      description: "Generic Alpha Generic Beta grouped payment",
      amount: "-100.00"
    )

    assert_no_difference "BasQuery.count" do
      assert_difference "BasMatch.count", 1 do
        BasMatching::Matcher.new(bas_job: job, actor_username: "phase3").call
      end
    end

    match = BasMatch.last
    assert_equal "invoices_to_bank_transaction", match.match_type
    assert_equal "proposed", match.status
    assert_equal "grouped_invoices_to_bank", match.created_by_rule
    assert_match "Multiple invoices total the same amount", match.explanation
    assert_equal BigDecimal("100.00"), match.matched_amount
    expected_items = [
      "BasInvoice:#{first_invoice.id}",
      "BasInvoice:#{second_invoice.id}",
      "BasBankTransaction:#{payment.id}"
    ].sort
    actual_items = match.items.map { |item| "#{item.matchable_type}:#{item.matchable_id}" }.sort
    assert_equal expected_items, actual_items
  end

  test "cross party grouped payment matching is idempotent" do
    job = bas_job
    invoice(job, direction: "purchase", party_name: "Generic Alpha", total_amount: "40.00", paid_date: Date.new(2026, 1, 4))
    invoice(job, direction: "purchase", party_name: "Generic Beta", total_amount: "60.00", paid_date: Date.new(2026, 1, 4))
    bank_transaction(job, transaction_date: Date.new(2026, 1, 4), description: "Generic Alpha Generic Beta grouped payment", amount: "-100.00")

    BasMatching::Matcher.new(bas_job: job, actor_username: "phase3").call

    assert_no_difference "BasMatch.count" do
      BasMatching::Matcher.new(bas_job: job, actor_username: "phase3").call
    end
  end

  test "grouped payment is not proposed when one invoice is already accepted elsewhere" do
    job = bas_job
    first_invoice = invoice(job, direction: "purchase", party_name: "Generic Alpha", total_amount: "40.00", paid_date: Date.new(2026, 1, 4))
    invoice(job, direction: "purchase", party_name: "Generic Beta", total_amount: "60.00", paid_date: Date.new(2026, 1, 4))
    bank_transaction(job, transaction_date: Date.new(2026, 1, 4), description: "Generic Alpha Generic Beta grouped payment", amount: "-100.00")
    accepted_payment = bank_transaction(job, transaction_date: Date.new(2026, 1, 4), description: "Generic Alpha accepted payment", amount: "-40.00")
    accepted_match = BasMatch.create!(bas_job: job, match_type: "manual", status: "accepted", accepted_by: "phase3", accepted_at: Time.current)
    accepted_match.items.create!(matchable: first_invoice, amount: first_invoice.total_amount)
    accepted_match.items.create!(matchable: accepted_payment, amount: accepted_payment.amount)

    assert_no_difference "BasMatch.count" do
      BasMatching::Matcher.new(bas_job: job, actor_username: "phase3").call
    end
  end

  test "grouped payment is not proposed when totals do not exactly match" do
    job = bas_job
    invoice(job, direction: "purchase", party_name: "Generic Alpha", total_amount: "40.00", paid_date: Date.new(2026, 1, 4))
    invoice(job, direction: "purchase", party_name: "Generic Beta", total_amount: "61.00", paid_date: Date.new(2026, 1, 4))
    bank_transaction(job, transaction_date: Date.new(2026, 1, 4), description: "Generic Alpha Generic Beta grouped payment", amount: "-100.00")

    assert_no_difference "BasMatch.count" do
      BasMatching::Matcher.new(bas_job: job, actor_username: "phase3").call
    end
  end

  test "grouped payment is not proposed when exact candidate groups are ambiguous" do
    job = bas_job
    invoice(job, direction: "purchase", party_name: "Generic Alpha", total_amount: "40.00", paid_date: Date.new(2026, 1, 4))
    invoice(job, direction: "purchase", party_name: "Generic Beta", total_amount: "60.00", paid_date: Date.new(2026, 1, 4))
    invoice(job, direction: "purchase", party_name: "Generic Gamma", total_amount: "30.00", paid_date: Date.new(2026, 1, 4))
    invoice(job, direction: "purchase", party_name: "Generic Delta", total_amount: "70.00", paid_date: Date.new(2026, 1, 4))
    bank_transaction(
      job,
      transaction_date: Date.new(2026, 1, 4),
      description: "Generic Alpha Generic Beta Generic Gamma Generic Delta grouped payment",
      amount: "-100.00"
    )

    assert_no_difference "BasMatch.count" do
      BasMatching::Matcher.new(bas_job: job, actor_username: "phase3").call
    end
  end

  test "rejected grouped payment match is not recreated" do
    job = bas_job
    invoice(job, direction: "purchase", party_name: "Generic Alpha", total_amount: "40.00", paid_date: Date.new(2026, 1, 4))
    invoice(job, direction: "purchase", party_name: "Generic Beta", total_amount: "60.00", paid_date: Date.new(2026, 1, 4))
    bank_transaction(job, transaction_date: Date.new(2026, 1, 4), description: "Generic Alpha Generic Beta grouped payment", amount: "-100.00")

    BasMatching::Matcher.new(bas_job: job, actor_username: "phase3").call
    match = BasMatch.last
    match.update!(status: "rejected", rejected_by: "phase3", rejected_at: Time.current)

    assert_no_difference "BasMatch.count" do
      BasMatching::Matcher.new(bas_job: job, actor_username: "phase3").call
    end

    assert_equal "rejected", match.reload.status
  end

  test "cash invoice matches cash transaction and is not forced to bank transaction" do
    job = bas_job
    invoice(job, party_name: "Cash Customer", total_amount: "33.00", payment_method: "cash")
    bank_transaction(job, description: "Cash Customer bank payment", amount: "33.00")
    cash_transaction(job, party_name: "Cash Customer", total_amount: "33.00")

    BasMatching::Matcher.new(bas_job: job, actor_username: "phase3").call

    assert_equal 1, BasMatch.count
    assert_equal "invoice_to_cash_transaction", BasMatch.last.match_type
  end

  test "matching is idempotent and accepted matches are preserved" do
    job = bas_job
    invoice(job, party_name: "Synthetic Customer", total_amount: "110.00")
    bank_transaction(job, description: "Synthetic Customer", amount: "110.00")

    BasMatching::Matcher.new(bas_job: job, actor_username: "phase3").call
    match = BasMatch.last
    match.update!(status: "accepted", accepted_by: "phase3", accepted_at: Time.current)

    assert_no_difference "BasMatch.count" do
      BasMatching::Matcher.new(bas_job: job, actor_username: "phase3").call
    end

    assert_equal "accepted", match.reload.status
  end

  test "rejected matches are not recreated immediately" do
    job = bas_job
    invoice(job, party_name: "Synthetic Customer", total_amount: "110.00")
    bank_transaction(job, description: "Synthetic Customer", amount: "110.00")

    BasMatching::Matcher.new(bas_job: job, actor_username: "phase3").call
    BasMatch.last.update!(status: "rejected", rejected_by: "phase3", rejected_at: Time.current)

    assert_no_difference "BasMatch.count" do
      BasMatching::Matcher.new(bas_job: job, actor_username: "phase3").call
    end
  end

  test "manual matches are preserved after matching rerun" do
    job = bas_job
    invoice_record = invoice(job, party_name: "Manual Customer", total_amount: "44.00")
    bank_record = bank_transaction(job, description: "Manual Customer", amount: "44.00")
    manual_match = BasMatch.create!(bas_job: job, match_type: "manual", status: "accepted", accepted_by: "phase3", accepted_at: Time.current)
    manual_match.items.create!(matchable: invoice_record, amount: invoice_record.total_amount)
    manual_match.items.create!(matchable: bank_record, amount: bank_record.amount)

    assert_no_difference "BasMatch.count" do
      BasMatching::Matcher.new(bas_job: job, actor_username: "phase3").call
    end

    assert_equal "accepted", manual_match.reload.status
  end

  test "query generation creates unmatched bank invoice gst and import error queries idempotently" do
    job = bas_job(payroll_applicable: true)
    invoice(job, party_name: "Unmatched Invoice", total_amount: "120.00", gst_code: "unknown", gst_amount: nil)
    bank_transaction(job, description: "Unmatched bank", amount: "99.00")
    import_run = BasImportRun.create!(
      bas_job: job,
      bas_document: bas_document(job),
      import_type: "bank_statement",
      status: "failed",
      row_count: 1,
      error_count: 1
    )
    import_run.import_errors = [ { "row_number" => 2, "message" => "Synthetic row error" } ]
    import_run.save!

    assert_difference "BasQuery.count", 6 do
      BasMatching::QueryGenerator.new(bas_job: job, actor_username: "phase3").call
    end

    assert_no_difference "BasQuery.count" do
      BasMatching::QueryGenerator.new(bas_job: job, actor_username: "phase3").call
    end

    assert job.queries.exists?(query_type: "unmatched_bank_transaction")
    assert job.queries.exists?(query_type: "unmatched_invoice")
    assert job.queries.exists?(query_type: "unreviewed_gst_code")
    assert job.queries.exists?(query_type: "gst_treatment_unclear")
    assert job.queries.exists?(query_type: "import_error")
    assert job.queries.exists?(query_type: "payroll_unclear")
  end

  test "query generation creates admin queries for unknown direction records" do
    job = bas_job
    invoice_record = invoice(job, direction: "unknown", status: "matched", gst_amount: BigDecimal("10.00"))
    cash_record = cash_transaction(job, direction: "unknown", gst_amount: BigDecimal("10.00"))

    assert_difference "BasQuery.count", 2 do
      BasMatching::QueryGenerator.new(bas_job: job, actor_username: "phase6b").call
    end

    assert job.queries.exists?(query_type: "invoice_direction_unclear", source_type: "BasInvoice", source_id: invoice_record.id)
    assert job.queries.exists?(query_type: "cash_transaction_direction_unclear", source_type: "BasCashTransaction", source_id: cash_record.id)
  end

  test "query generation treats records with only rejected matches as unmatched" do
    job = bas_job
    invoice_record = invoice(job, party_name: "Rejected Match Customer", total_amount: "110.00", gst_amount: "10.00")
    bank_record = bank_transaction(job, description: "Rejected Match Customer", amount: "110.00")
    match = BasMatch.create!(
      bas_job: job,
      match_type: "invoice_to_bank_transaction",
      status: "rejected",
      rejected_at: Time.current,
      rejected_by: "phase6"
    )
    match.items.create!(matchable: invoice_record, amount: invoice_record.total_amount)
    match.items.create!(matchable: bank_record, amount: bank_record.amount)

    assert_difference "BasQuery.count", 2 do
      BasMatching::QueryGenerator.new(bas_job: job, actor_username: "phase6").call
    end

    assert job.queries.exists?(query_type: "unmatched_bank_transaction", source_type: "BasBankTransaction", source_id: bank_record.id)
    assert job.queries.exists?(query_type: "unmatched_invoice", source_type: "BasInvoice", source_id: invoice_record.id)
  end

  test "locked job blocks matching and query generation" do
    job = bas_job(status: "locked")

    assert_raises(BasMatching::Matcher::LockedJobError) do
      BasMatching::Matcher.new(bas_job: job, actor_username: "phase3").call
    end

    assert_raises(BasMatching::QueryGenerator::LockedJobError) do
      BasMatching::QueryGenerator.new(bas_job: job, actor_username: "phase3").call
    end
  end

  private

  def bas_job(attributes = {})
    BasJob.create!({
      bas_client: BasClient.create!(legal_name: "Synthetic Matching Client Pty Ltd"),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31)
    }.merge(attributes))
  end

  def invoice(job, attributes = {})
    BasInvoice.create!({
      bas_job: job,
      direction: "sale",
      invoice_number: "INV-#{SecureRandom.hex(2)}",
      issue_date: Date.new(2026, 1, 1),
      paid_date: Date.new(2026, 1, 2),
      party_name: "Synthetic Customer",
      total_amount: BigDecimal("110.00"),
      payment_method: "bank",
      gst_code: "taxable",
      status: "imported"
    }.merge(attributes))
  end

  def bank_transaction(job, attributes = {})
    BasBankTransaction.create!({
      bas_job: job,
      transaction_date: Date.new(2026, 1, 2),
      description: "Synthetic Customer payment",
      amount: BigDecimal("110.00"),
      status: "imported"
    }.merge(attributes))
  end

  def cash_transaction(job, attributes = {})
    BasCashTransaction.create!({
      bas_job: job,
      transaction_date: Date.new(2026, 1, 2),
      party_name: "Synthetic Customer",
      description: "Synthetic cash payment",
      total_amount: BigDecimal("110.00"),
      gst_code: "taxable",
      status: "imported"
    }.merge(attributes))
  end

  def bas_document(job)
    document = job.documents.build(title: "Synthetic import", document_type: "bank_statement")
    document.file.attach(
      io: StringIO.new("Date,Description,Amount\n01/01/2026,Synthetic,1.00\n"),
      filename: "synthetic.csv",
      content_type: "text/csv"
    )
    document.save!
    document
  end
end
