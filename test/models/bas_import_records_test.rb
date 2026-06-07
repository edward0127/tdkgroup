require "test_helper"

class BasImportRecordsTest < ActiveSupport::TestCase
  test "bas import run validates allowlists and document job ownership" do
    job = bas_job
    other_job = bas_job(legal_name: "Other Synthetic Client Pty Ltd")
    document = bas_document(other_job)

    import_run = BasImportRun.new(
      bas_job: job,
      bas_document: document,
      import_type: "bank_statement",
      status: "previewed"
    )

    assert_not import_run.valid?
    assert_includes import_run.errors[:bas_document], "must belong to the same BAS job"

    import_run.bas_document = bas_document(job)
    import_run.import_type = "unsupported"
    import_run.status = "unknown"

    assert_not import_run.valid?
    assert_equal :inclusion, import_run.errors.details[:import_type].first.fetch(:error)
    assert_equal :inclusion, import_run.errors.details[:status].first.fetch(:error)
  end

  test "bank transaction validates status allowlist" do
    transaction = BasBankTransaction.new(bas_job: bas_job, status: "imported")
    assert transaction.valid?, transaction.errors.full_messages.to_sentence

    transaction.status = "posted"
    assert_not transaction.valid?
    assert_equal :inclusion, transaction.errors.details[:status].first.fetch(:error)
  end

  test "invoice validates allowlists" do
    invoice = BasInvoice.new(
      bas_job: bas_job,
      direction: "sale",
      payment_method: "bank",
      gst_code: "taxable",
      status: "imported"
    )

    assert invoice.valid?, invoice.errors.full_messages.to_sentence

    invoice.direction = "refund"
    invoice.payment_method = "cheque_only"
    invoice.gst_code = "guess"
    invoice.status = "posted"

    assert_not invoice.valid?
    assert_equal :inclusion, invoice.errors.details[:direction].first.fetch(:error)
    assert_equal :inclusion, invoice.errors.details[:payment_method].first.fetch(:error)
    assert_equal :inclusion, invoice.errors.details[:gst_code].first.fetch(:error)
    assert_equal :inclusion, invoice.errors.details[:status].first.fetch(:error)
  end

  test "cash transaction validates allowlists" do
    transaction = BasCashTransaction.new(
      bas_job: bas_job,
      direction: "cash_receipt",
      gst_code: "taxable",
      status: "imported"
    )

    assert transaction.valid?, transaction.errors.full_messages.to_sentence

    transaction.direction = "card"
    transaction.gst_code = "guess"
    transaction.status = "matched"

    assert_not transaction.valid?
    assert_equal :inclusion, transaction.errors.details[:direction].first.fetch(:error)
    assert_equal :inclusion, transaction.errors.details[:gst_code].first.fetch(:error)
    assert_equal :inclusion, transaction.errors.details[:status].first.fetch(:error)
  end

  test "payroll summary requires at least one amount" do
    summary = BasPayrollSummary.new(bas_job: bas_job)

    assert_not summary.valid?
    assert_includes summary.errors[:base], "At least one payroll amount must be present"

    summary.gross_wages = BigDecimal("1000.00")
    assert summary.valid?, summary.errors.full_messages.to_sentence
  end

  private

  def bas_job(legal_name: "Synthetic Client Pty Ltd")
    client = BasClient.create!(legal_name: legal_name)
    BasJob.create!(
      bas_client: client,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31)
    )
  end

  def bas_document(job)
    document = job.documents.build(title: "Synthetic bank statement", document_type: "bank_statement")
    document.file.attach(
      io: StringIO.new(File.binread(Rails.root.join("test/fixtures/files/bas_bank_statement.csv"))),
      filename: "bas_bank_statement.csv",
      content_type: "text/csv"
    )
    document.save!
    document
  end
end
