require "test_helper"

class BasReportsTest < ActiveSupport::TestCase
  test "taxable sale calculation contributes to G1 and 1A" do
    job = bas_job
    invoice(job, direction: "sale", total_amount: "110.00", gst_amount: "10.00")

    result = calculate(job)

    assert_equal "110.00", summary(result)["g1_total_sales"]
    assert_equal "10.00", summary(result)["gst_on_sales_1a"]
  end

  test "taxable purchase calculation contributes to 1B" do
    job = bas_job
    invoice(job, direction: "purchase", total_amount: "55.00", gst_amount: "5.00")

    result = calculate(job)

    assert_equal "5.00", summary(result)["gst_on_purchases_1b"]
  end

  test "bas excluded and ignored items are excluded" do
    job = bas_job
    invoice(job, direction: "sale", total_amount: "110.00", gst_amount: "10.00", gst_code: "bas_excluded")
    invoice(job, direction: "sale", total_amount: "220.00", gst_amount: "20.00", status: "ignored")

    result = calculate(job)

    assert_equal "0.00", summary(result)["g1_total_sales"]
    assert_equal "0.00", summary(result)["gst_on_sales_1a"]
    assert_equal 2, result.totals.fetch("ignored_items").size
  end

  test "unknown GST code blocks approval" do
    job = bas_job
    invoice(job, gst_code: "unknown", gst_amount: nil)

    blockers = BasReports::ApprovalValidator.new(bas_job: job).call

    assert blockers.any? { |blocker| blocker.include?("unknown GST treatment") }
  end

  test "invoice with unknown direction blocks approval and calculation" do
    job = bas_job
    invoice_record = invoice(job, direction: "unknown", status: "matched")

    blockers = BasReports::ApprovalValidator.new(bas_job: job).call
    result = calculate(job)

    assert blockers.any? { |blocker| blocker.include?("invoice") && blocker.include?("unknown direction") }
    assert result.validation_errors.any? { |error| error.include?("Invoice ##{invoice_record.id}") && error.include?("unknown direction") }
  end

  test "cash transaction with unknown direction blocks approval and calculation" do
    job = bas_job
    transaction = cash_transaction(job, direction: "unknown")

    blockers = BasReports::ApprovalValidator.new(bas_job: job).call
    result = calculate(job)

    assert blockers.any? { |blocker| blocker.include?("cash transaction") && blocker.include?("unknown direction") }
    assert result.validation_errors.any? { |error| error.include?("Cash transaction ##{transaction.id}") && error.include?("unknown direction") }
  end

  test "ignored unknown direction records do not block approval" do
    job = bas_job
    invoice(job, direction: "unknown", status: "ignored")
    cash_transaction(job, direction: "unknown", status: "ignored")

    blockers = BasReports::ApprovalValidator.new(bas_job: job).call
    result = calculate(job)

    assert_empty blockers.grep(/unknown direction/)
    assert_empty result.validation_errors.grep(/unknown direction/)
  end

  test "bas excluded unknown direction records do not block approval" do
    job = bas_job
    invoice(job, direction: "unknown", gst_code: "bas_excluded", status: "matched")
    cash_transaction(job, direction: "unknown", gst_code: "bas_excluded")

    blockers = BasReports::ApprovalValidator.new(bas_job: job).call
    result = calculate(job)

    assert_empty blockers.grep(/unknown direction/)
    assert_empty result.validation_errors.grep(/unknown direction/)
  end

  test "cash basis uses accepted match payment date" do
    job = bas_job(gst_basis: "cash")
    invoice_record = invoice(job, issue_date: Date.new(2025, 12, 1), total_amount: "110.00", gst_amount: "10.00", status: "matched")
    bank_record = bank_transaction(job, transaction_date: Date.new(2026, 1, 10), amount: "110.00", status: "matched")
    accepted_match(job, invoice_record, bank_record, matched_amount: "110.00")

    result = calculate(job)

    assert_equal "110.00", summary(result)["g1_total_sales"]
    assert_equal "10.00", summary(result)["gst_on_sales_1a"]
  end

  test "cash basis allocates partial matched payments proportionally" do
    job = bas_job(gst_basis: "cash")
    invoice_record = invoice(job, total_amount: "110.00", gst_amount: "10.00", status: "matched")
    bank_record = bank_transaction(job, amount: "55.00", status: "matched")
    accepted_match(job, invoice_record, bank_record, matched_amount: "55.00")

    result = calculate(job)

    assert_equal "55.00", summary(result)["g1_total_sales"]
    assert_equal "5.00", summary(result)["gst_on_sales_1a"]
  end

  test "accrual basis uses invoice issue date and ignores payment timing" do
    job = bas_job(gst_basis: "accrual")
    invoice_record = invoice(job, issue_date: Date.new(2026, 1, 15), total_amount: "110.00", gst_amount: "10.00", status: "matched")
    bank_record = bank_transaction(job, transaction_date: Date.new(2026, 4, 1), amount: "110.00", status: "matched")
    accepted_match(job, invoice_record, bank_record, matched_amount: "110.00")

    result = calculate(job)

    assert_equal "110.00", summary(result)["g1_total_sales"]
    assert_equal "10.00", summary(result)["gst_on_sales_1a"]
  end

  test "cash receipt and cash payment contribute to GST totals" do
    job = bas_job
    cash_transaction(job, direction: "cash_receipt", total_amount: "55.00", gst_amount: "5.00")
    cash_transaction(job, direction: "cash_payment", total_amount: "33.00", gst_amount: "3.00")

    result = calculate(job)

    assert_equal "55.00", summary(result)["g1_total_sales"]
    assert_equal "5.00", summary(result)["gst_on_sales_1a"]
    assert_equal "3.00", summary(result)["gst_on_purchases_1b"]
  end

  test "payroll comes from summaries and manual payroll adjustments" do
    job = bas_job(payroll_applicable: true)
    BasPayrollSummary.create!(
      bas_job: job,
      gross_wages: BigDecimal("1000.00"),
      payg_withheld: BigDecimal("200.00"),
      super_amount: BigDecimal("110.00")
    )
    adjustment(job, adjustment_type: "payroll_gross_wages", amount: "50.00")
    adjustment(job, adjustment_type: "payg_withheld", amount: "10.00")

    result = calculate(job)
    payroll = result.totals.fetch("payroll")

    assert_equal "1050.00", payroll["gross_wages"]
    assert_equal "210.00", payroll["payg_withheld"]
    assert_equal "110.00", payroll["super_amount"]
    assert_equal "0.00", summary(result)["gst_on_purchases_1b"]
  end

  test "manual adjustments are included and require reasons" do
    job = bas_job
    adjustment(job, adjustment_type: "total_sales", amount: "20.00")
    adjustment(job, adjustment_type: "gst_on_sales", amount: "2.00")
    adjustment(job, adjustment_type: "gst_on_purchases", amount: "1.00")

    result = calculate(job)

    assert_equal "20.00", summary(result)["g1_total_sales"]
    assert_equal "2.00", summary(result)["gst_on_sales_1a"]
    assert_equal "1.00", summary(result)["gst_on_purchases_1b"]

    invalid = BasAdjustment.new(bas_job: job, adjustment_type: "other", label: "No reason", amount: BigDecimal("1.00"))
    assert_not invalid.valid?
  end

  test "approval blocks open queries import errors proposed matches and unmatched records unless ignored" do
    job = bas_job
    invoice_record = invoice(job)
    bank_transaction(job)
    BasQuery.create!(bas_job: job, title: "Synthetic open query")
    BasImportRun.create!(
      bas_job: job,
      bas_document: bas_document(job),
      import_type: "bank_statement",
      status: "failed",
      error_count: 1,
      row_errors: [ { "row_number" => 2, "message" => "Synthetic row error" } ]
    )
    BasMatch.create!(
      bas_job: job,
      match_type: "invoice_to_bank_transaction",
      status: "proposed"
    )

    blockers = BasReports::ApprovalValidator.new(bas_job: job).call

    assert blockers.any? { |blocker| blocker.include?("open BAS query") }
    assert blockers.any? { |blocker| blocker.include?("row errors") }
    assert blockers.any? { |blocker| blocker.include?("proposed match") }
    assert blockers.any? { |blocker| blocker.include?("bank transaction") }
    assert blockers.any? { |blocker| blocker.include?("invoice") }

    invoice_record.update!(status: "ignored")
    job.bank_transactions.update_all(status: "ignored")

    blockers = BasReports::ApprovalValidator.new(bas_job: job).call
    assert blockers.none? { |blocker| blocker.include?("remain unmatched") }
  end

  test "approval treats records with only rejected matches as unmatched" do
    job = bas_job
    invoice_record = invoice(job)
    bank_record = bank_transaction(job)
    match = BasMatch.create!(
      bas_job: job,
      match_type: "invoice_to_bank_transaction",
      status: "rejected",
      rejected_at: Time.current,
      rejected_by: "phase6"
    )
    match.items.create!(matchable: invoice_record, amount: invoice_record.total_amount)
    match.items.create!(matchable: bank_record, amount: bank_record.amount)

    blockers = BasReports::ApprovalValidator.new(bas_job: job).call

    assert blockers.any? { |blocker| blocker.include?("bank transaction") && blocker.include?("remain unmatched") }
    assert blockers.any? { |blocker| blocker.include?("invoice") && blocker.include?("remain unmatched") }
  end

  test "snapshot builder preserves totals and final snapshot cannot be changed" do
    job = clean_matched_job

    snapshot = BasReports::SnapshotBuilder.new(bas_job: job, actor_username: "phase4").create_draft!

    assert_equal "110.00", snapshot.totals.fetch("summary").fetch("g1_total_sales")
    assert_equal "report_ready", job.reload.status
    assert_equal "phase4", snapshot.generated_by

    BasReports::SnapshotBuilder.new(bas_job: job, actor_username: "phase4").approve!(snapshot: snapshot)
    assert_equal "approved", job.reload.status
    assert_equal "final", snapshot.reload.status
    assert_not snapshot.update(totals: { "summary" => { "g1_total_sales" => "999.00" } })
  end

  test "locked job blocks report-changing service actions" do
    job = bas_job(status: "locked")

    assert_raises(BasReports::SnapshotBuilder::LockedJobError) do
      BasReports::SnapshotBuilder.new(bas_job: job, actor_username: "phase4").create_draft!
    end
  end

  test "csv exporter escapes formula-like cells" do
    job = bas_job
    BasAdjustment.create!(
      bas_job: job,
      adjustment_type: "other",
      label: "=formula",
      amount: BigDecimal("-1.00"),
      reason: "@reason"
    )
    snapshot = BasReports::SnapshotBuilder.new(bas_job: job, actor_username: "phase4").create_draft!

    csv = BasReports::CsvExporter.new(snapshot: snapshot).adjustments_csv

    assert_includes csv, "'=formula"
    assert_includes csv, "'-1.00"
    assert_includes csv, "'@reason"
  end

  private

  def calculate(job)
    BasReports::Calculator.new(bas_job: job).call
  end

  def summary(result)
    result.totals.fetch("summary")
  end

  def bas_job(attributes = {})
    BasJob.create!({
      bas_client: BasClient.create!(legal_name: "Synthetic Report Client Pty Ltd"),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      gst_basis: "accrual",
      reporting_method: "simpler_bas",
      payroll_applicable: false
    }.merge(attributes))
  end

  def clean_matched_job
    job = bas_job
    invoice_record = invoice(job, status: "matched")
    bank_record = bank_transaction(job, status: "matched")
    accepted_match(job, invoice_record, bank_record)
    job
  end

  def invoice(job, attributes = {})
    BasInvoice.create!({
      bas_job: job,
      direction: "sale",
      invoice_number: "INV-#{SecureRandom.hex(2)}",
      issue_date: Date.new(2026, 1, 15),
      party_name: "Synthetic Customer",
      total_amount: BigDecimal("110.00"),
      gst_amount: BigDecimal("10.00"),
      payment_method: "bank",
      gst_code: "taxable",
      status: "imported"
    }.merge(attributes))
  end

  def bank_transaction(job, attributes = {})
    BasBankTransaction.create!({
      bas_job: job,
      transaction_date: Date.new(2026, 1, 20),
      description: "Synthetic Customer payment",
      amount: BigDecimal("110.00"),
      status: "imported"
    }.merge(attributes))
  end

  def cash_transaction(job, attributes = {})
    BasCashTransaction.create!({
      bas_job: job,
      transaction_date: Date.new(2026, 1, 20),
      party_name: "Synthetic Cash Customer",
      description: "Synthetic cash transaction",
      direction: "cash_receipt",
      total_amount: BigDecimal("55.00"),
      gst_amount: BigDecimal("5.00"),
      gst_code: "taxable",
      status: "imported"
    }.merge(attributes))
  end

  def accepted_match(job, invoice_record, payment_record, attributes = {})
    match = BasMatch.create!({
      bas_job: job,
      match_type: payment_record.is_a?(BasCashTransaction) ? "invoice_to_cash_transaction" : "invoice_to_bank_transaction",
      status: "accepted",
      matched_amount: invoice_record.total_amount,
      accepted_at: Time.current,
      accepted_by: "phase4"
    }.merge(attributes))
    match.items.create!(matchable: invoice_record, amount: invoice_record.total_amount)
    amount = payment_record.respond_to?(:amount) ? payment_record.amount : payment_record.total_amount
    match.items.create!(matchable: payment_record, amount: amount)
    match
  end

  def adjustment(job, attributes = {})
    BasAdjustment.create!({
      bas_job: job,
      adjustment_type: "gst_on_sales",
      label: "Synthetic adjustment",
      amount: BigDecimal("1.00"),
      reason: "Synthetic review reason",
      created_by: "phase4"
    }.merge(attributes))
  end

  def bas_document(job)
    document = job.documents.build(title: "Synthetic bank statement", document_type: "bank_statement")
    document.file.attach(
      io: StringIO.new("Date,Description,Amount\n01/01/2026,Synthetic,1.00\n"),
      filename: "synthetic.csv",
      content_type: "text/csv"
    )
    document.save!
    document
  end
end
