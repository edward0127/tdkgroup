require "test_helper"

class AdminBasJobNextStepPresenterTest < ActiveSupport::TestCase
  test "no files recommends uploading source files" do
    job = bas_job

    assert_equal "Next step: Upload source files", presenter(job).title
  end

  test "uploaded importable files recommend importing data" do
    job = bas_job
    bas_document(job)

    assert_equal "Next step: Import uploaded files", presenter(job).title
  end

  test "import errors recommend reviewing imports" do
    job = bas_job
    document = bas_document(job)
    BasImportRun.create!(
      bas_job: job,
      bas_document: document,
      import_type: "bank_statement",
      status: "failed",
      error_count: 1,
      row_errors: [ { "row_number" => 2, "error" => "Bad date" } ]
    )

    assert_equal "Next step: Fix import errors", presenter(job).title
  end

  test "imported records without matches recommend creating match suggestions" do
    job = bas_job
    bank_transaction(job, status: "ignored")

    assert_equal "Next step: Create match suggestions", presenter(job).title
  end

  test "proposed matches recommend match review" do
    job = bas_job
    bank_transaction(job, status: "ignored")
    bas_match(job, status: "proposed")

    assert_equal "Next step: Review match suggestions", presenter(job).title
  end

  test "unresolved records after match review recommend generating queries" do
    job = bas_job
    bank_transaction(job, status: "imported")
    bas_match(job, status: "accepted")

    assert_equal "Next step: Generate client queries", presenter(job).title
  end

  test "open queries recommend resolving queries" do
    job = bas_job
    bank_transaction(job, status: "imported")
    bas_match(job, status: "accepted")
    BasQuery.create!(bas_job: job, title: "Review unmatched transaction", query_type: "unmatched_bank_transaction")

    assert_equal "Next step: Resolve open queries", presenter(job).title
  end

  test "ready job recommends calculating BAS draft" do
    job = bas_job
    bank_transaction(job, status: "ignored")
    bas_match(job, status: "accepted")

    assert_equal "Next step: Calculate BAS draft", presenter(job).title
  end

  test "draft snapshot recommends reviewing draft" do
    job = bas_job
    bank_transaction(job, status: "ignored")
    bas_match(job, status: "accepted")
    report_snapshot(job, status: "draft")

    assert_equal "Next step: Review draft snapshot", presenter(job).title
  end

  test "final snapshot recommends locking job" do
    job = bas_job
    bank_transaction(job, status: "ignored")
    bas_match(job, status: "accepted")
    report_snapshot(job, status: "final", approved_at: Time.current, approved_by: "next-step-test")

    assert_equal "Next step: Lock BAS job", presenter(job).title
  end

  test "locked job has no mutation action" do
    job = bas_job(status: "locked", locked_at: Time.current, locked_by: "next-step-test")

    assert_equal "BAS job locked", presenter(job).title
    assert_not presenter(job).action?
  end

  private

  def presenter(job)
    Admin::Bas::JobNextStepPresenter.new(job: job)
  end

  def bas_job(attributes = {})
    BasJob.create!({
      bas_client: BasClient.create!(legal_name: "Synthetic Next Step Client Pty Ltd"),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      gst_basis: "cash",
      reporting_method: "simpler_bas"
    }.merge(attributes))
  end

  def bas_document(job)
    document = job.documents.build(
      title: "Synthetic bank statement",
      document_type: "bank_statement",
      uploaded_by: "next-step-test"
    )
    document.file.attach(
      io: StringIO.new("Date,Description,Amount\n01/01/2026,Synthetic,1.00\n"),
      filename: "synthetic-next-step.csv",
      content_type: "text/csv"
    )
    document.save!
    document
  end

  def bank_transaction(job, status:)
    BasBankTransaction.create!(
      bas_job: job,
      transaction_date: Date.new(2026, 1, 5),
      description: "Synthetic next step transaction",
      amount: BigDecimal("100.00"),
      status: status
    )
  end

  def bas_match(job, status:)
    BasMatch.create!(
      bas_job: job,
      match_type: "manual",
      status: status,
      matched_amount: BigDecimal("100.00")
    )
  end

  def report_snapshot(job, attributes = {})
    BasReportSnapshot.create!({
      bas_job: job,
      status: "draft",
      totals: { "summary" => { "gst_payable" => "0.00" } },
      generated_at: Time.current,
      generated_by: "next-step-test"
    }.merge(attributes))
  end
end
