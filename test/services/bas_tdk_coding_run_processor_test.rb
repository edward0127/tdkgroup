require "test_helper"

class BasTdkCodingRunProcessorTest < ActiveSupport::TestCase
  test "copies unanimous same-direction exact history with signed GST and provenance" do
    job = create_job
    workbook = create_workbook(job)
    row = create_row(workbook, description: "Card payment OFFICEWORKS 30/06/2026", amount: "-363.00")
    run = create_run(job, workbook, reference_csv: <<~CSV)
      Description,Category,Amount,GST
      OFFICEWORKS REF 111111,Office expenses,-121.00,-11.00
      OFFICEWORKS REF 222222,Office expenses,-242.00,-22.00
    CSV

    process(run)

    coding = run.reload.row_codings.find_by!(workbook_row: row)
    assert_equal "processed", run.status
    assert_equal "Office expenses", coding.suggested_category
    assert_equal BigDecimal("-33"), coding.suggested_gst_amount
    assert_equal "previous_quarter_exact", coding.category_source
    assert_equal "previous_quarter_exact", coding.gst_source
    refute coding.category_review_required
    refute coding.gst_review_required
    assert_equal "standard_taxable", coding.metadata.fetch("gst_consensus_status")
    assert_equal "Office expenses", row.reload.row_data.fetch("Category")
    assert_equal "-33.00", row.row_data.fetch("GST")
    assert_equal "stale", workbook.reload.export_status
    assert_equal 0, run.warning_count
  end

  test "tolerates cents-rounded one-eleventh ratios across repeated historical transactions" do
    job = create_job
    workbook = create_workbook(job)
    row = create_row(workbook, description: "Adobe Creative Cloud", amount: "-110.00")
    run = create_run(job, workbook, reference_csv: <<~CSV)
      Description,Category,Amount,GST
      Adobe Creative Cloud,Software,-19.95,-1.81
      Adobe Creative Cloud,Software,-54.40,-4.95
    CSV

    process(run)

    coding = run.reload.row_codings.find_by!(workbook_row: row)
    assert_equal "previous_quarter_exact", coding.category_source
    assert_equal BigDecimal("-10"), coding.suggested_gst_amount
    assert_equal "standard_taxable", coding.metadata.fetch("gst_consensus_status")
  end

  test "uses a positive historical ratio so a positive-magnitude source GST cannot flip debit GST positive" do
    job = create_job
    workbook = create_workbook(job)
    row = create_row(workbook, description: "Cloud Hosting", amount: "-242.00")
    run = create_run(job, workbook, reference_csv: <<~CSV)
      Description,Category,Amount,GST
      Cloud Hosting,Hosting,-121.00,11.00
    CSV

    process(run)

    coding = run.reload.row_codings.find_by!(workbook_row: row)
    assert_equal BigDecimal("-22"), coding.suggested_gst_amount
    assert_equal "11.0", coding.reference_snapshot.fetch("gst_amount")
  end

  test "does not copy opposite-direction history or conflicting historical categories" do
    job = create_job
    workbook = create_workbook(job)
    credit = create_row(workbook, position: 1, description: "OFFICEWORKS", amount: "121.00")
    conflict = create_row(workbook, position: 2, description: "Adobe Cloud", amount: "-110.00")
    run = create_run(job, workbook, reference_csv: <<~CSV)
      Description,Category,Amount,GST
      OFFICEWORKS,Office expenses,-121.00,-11.00
      Adobe Cloud,Software,-121.00,-11.00
      Adobe Cloud,Office expenses,-242.00,-22.00
    CSV

    process(run)

    credit_coding = run.reload.row_codings.find_by!(workbook_row: credit)
    conflict_coding = run.row_codings.find_by!(workbook_row: conflict)
    assert_equal "unmatched", credit_coding.category_source
    assert_nil credit_coding.suggested_gst_amount
    assert_equal "rule", conflict_coding.category_source
    assert_equal "Software & subscriptions", conflict_coding.suggested_category
    assert conflict_coding.review_required?
  end

  test "keeps category history when historical GST conflicts but leaves GST for review" do
    job = create_job
    workbook = create_workbook(job)
    row = create_row(workbook, description: "Synthetic Supplier", amount: "-330.00")
    run = create_run(job, workbook, reference_csv: <<~CSV)
      Description,Category,Amount,GST
      Synthetic Supplier,Consulting,-110.00,-10.00
      Synthetic Supplier,Consulting,-220.00,0.00
    CSV

    process(run)

    coding = run.reload.row_codings.find_by!(workbook_row: row)
    assert_equal "previous_quarter_exact", coding.category_source
    assert_equal "Consulting", coding.suggested_category
    assert_equal "unmatched", coding.gst_source
    assert_nil coding.suggested_gst_amount
    refute coding.category_review_required
    assert coding.gst_review_required
    assert_includes coding.warning_codes, "historical_gst_conflict"
    assert_equal 1, run.warning_count
  end

  test "mixed zero-GST treatments are a conflict rather than a silent no-GST consensus" do
    job = create_job
    workbook = create_workbook(job)
    row = create_row(workbook, description: "Synthetic Zero Supplier", amount: "-100.00")
    run = create_run(job, workbook, reference_csv: <<~CSV)
      Description,Category,Amount,GST
      Synthetic Zero Supplier,Other,-50.00,GST Free
      Synthetic Zero Supplier,Other,-50.00,Input taxed
    CSV

    process(run)

    coding = run.reload.row_codings.find_by!(workbook_row: row)
    assert_equal "previous_quarter_exact", coding.category_source
    assert_nil coding.suggested_gst_amount
    assert_equal "needs_review", coding.gst_treatment
    assert_includes coding.warning_codes, "historical_gst_conflict"
    assert_includes coding.explanation, "GST was missing or conflicted"
  end

  test "high-threshold fuzzy history is always highlighted for review" do
    job = create_job
    workbook = create_workbook(job)
    row = create_row(workbook, description: "Adobe Creative Cloud subscriptio", amount: "-121.00")
    run = create_run(job, workbook, reference_csv: <<~CSV)
      Description,Category,Amount,GST
      Adobe Creative Cloud subscription,Software,-121.00,-11.00
    CSV

    process(run)

    coding = run.reload.row_codings.find_by!(workbook_row: row)
    assert_equal "previous_quarter_fuzzy", coding.category_source
    assert coding.category_review_required
    assert coding.gst_review_required
    assert_includes coding.warning_codes, "fuzzy_previous_quarter_match"
  end

  test "preserves existing manual values and later edits across coding runs" do
    job = create_job
    workbook = create_workbook(job)
    row = create_row(
      workbook,
      description: "Adobe Creative Cloud",
      amount: "-121.00",
      category: "Owner reviewed category",
      gst: "(9.00)"
    )
    first = create_run(job, workbook, reference_csv: reference_for_adobe)

    process(first)

    first_coding = first.reload.row_codings.find_by!(workbook_row: row)
    assert_equal "manual", first_coding.category_source
    assert_equal "manual", first_coding.gst_source
    assert_equal BigDecimal("-9"), first_coding.suggested_gst_amount
    assert_equal "Owner reviewed category", row.reload.row_data.fetch("Category")
    assert_equal "(9.00)", row.row_data.fetch("GST")

    row.update!(row_data: row.row_data.merge("Category" => "Changed after run", "GST" => "GST included"))
    second = create_run(job, workbook, version_number: 2, reference_csv: reference_for_adobe)
    process(second)

    second_coding = second.reload.row_codings.find_by!(workbook_row: row)
    assert_equal "manual", second_coding.category_source
    assert_equal "manual", second_coding.gst_source
    assert_equal BigDecimal("-11"), second_coding.suggested_gst_amount
    assert_equal "Changed after run", row.reload.row_data.fetch("Category")
    assert_equal "GST included", row.row_data.fetch("GST")
  end

  test "preserves a later manual clearing without overwriting it with a new suggestion" do
    job = create_job
    workbook = create_workbook(job)
    row = create_row(workbook, description: "Adobe Creative Cloud", amount: "-121.00")
    first = create_run(job, workbook, reference_csv: reference_for_adobe)
    process(first)
    row.reload.update!(row_data: row.row_data.merge("Category" => "", "GST" => ""))

    second = create_run(job, workbook, version_number: 2, reference_csv: reference_for_adobe)
    process(second)

    coding = second.reload.row_codings.find_by!(workbook_row: row)
    assert_nil coding.suggested_category
    assert_nil coding.suggested_gst_amount
    assert_equal "unmatched", coding.category_source
    assert_equal "unmatched", coding.gst_source
    assert coding.category_review_required
    assert coding.gst_review_required
    assert_equal "", row.reload.row_data.fetch("Category")
    assert_equal "", row.row_data.fetch("GST")
  end

  test "confirmed mapping is consumed on the next pass instead of looping in needs mapping" do
    job = create_job
    workbook = create_workbook(job)
    row = create_row(workbook, description: "Adobe Creative Cloud", amount: "-121.00")
    run = create_run(job, workbook, reference_csv: <<~CSV)
      Description,Description,Category,Amount,GST
      Adobe,Adobe Creative Cloud,Software,-121.00,-11.00
    CSV

    process(run)
    assert_equal "needs_mapping", run.reload.status

    run.update!(
      status: "processing",
      column_mapping: { "description" => 2, "category" => 3, "amount" => 4, "gst" => 5 },
      header_row_number: 1,
      data_start_row: 2,
      row_errors: []
    )
    process(run)

    assert_equal "processed", run.reload.status
    coding = run.row_codings.find_by!(workbook_row: row)
    assert_equal "previous_quarter_exact", coding.category_source
    assert_equal BigDecimal("-11"), coding.suggested_gst_amount
  end

  test "supersedes a run pinned to a bank statement that is no longer active" do
    job = create_job
    old_workbook = create_workbook(job, version_number: 1)
    row = create_row(old_workbook, description: "Adobe Creative Cloud", amount: "-121.00")
    run = create_run(job, old_workbook, reference_csv: reference_for_adobe)
    create_workbook(job, version_number: 2)

    assert_no_difference "BasTdkRowCoding.count" do
      process(run)
    end

    assert_equal "superseded", run.reload.status
    assert_includes run.processing_errors.to_sentence, "no longer the active"
    assert_equal "", row.reload.row_data.fetch("Category")
    assert_equal "", row.row_data.fetch("GST")
  end

  private

  def create_job
    BasJob.create!(
      bas_client: BasClient.create!(legal_name: "Synthetic Coding Processor Client #{SecureRandom.hex(4)} Pty Ltd"),
      period_start: Date.new(2026, 4, 1),
      period_end: Date.new(2026, 6, 30),
      workflow_type: "tdk_group",
      gst_basis: "accrual",
      reporting_method: "simpler_bas"
    )
  end

  def create_workbook(job, version_number: 1)
    job.tdk_workbooks.create!(
      version_number: version_number,
      status: "processed",
      source_filename: "current-quarter-v#{version_number}.csv",
      processed_headers: %w[Date Category Amount GST Description],
      export_status: "processed",
      processed_at: Time.current
    )
  end

  def create_row(workbook, position: 1, description:, amount:, category: "", gst: "")
    workbook.rows.create!(
      position: position,
      source_row_number: position + 1,
      row_data: {
        "Date" => "2026-06-30",
        "Category" => category,
        "Amount" => amount,
        "GST" => gst,
        "Description" => description
      }
    )
  end

  def create_run(job, workbook, version_number: 1, reference_csv:)
    run = job.tdk_coding_runs.create!(
      target_workbook: workbook,
      version_number: version_number,
      status: "processing",
      source_filename: "prior-quarter.csv"
    )
    run.reference_file.attach(
      io: StringIO.new(reference_csv),
      filename: "prior-quarter.csv",
      content_type: "text/csv"
    )
    run
  end

  def process(run)
    BasTdk::CodingRunProcessor.new(coding_run: run, actor_username: "processor-test").call
  end

  def reference_for_adobe
    <<~CSV
      Description,Category,Amount,GST
      Adobe Creative Cloud,Software,-121.00,-11.00
    CSV
  end
end
