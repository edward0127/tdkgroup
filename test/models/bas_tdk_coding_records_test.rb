require "test_helper"

class BasTdkCodingRecordsTest < ActiveSupport::TestCase
  test "coding run exposes workflow states scopes attachment and normalized JSON" do
    job = create_job
    workbook = create_workbook(job, version_number: 1)
    older = create_coding_run(
      job,
      workbook,
      version_number: 1,
      status: "processed",
      original_headers: nil,
      column_mapping: nil,
      row_errors: nil,
      metadata: nil
    )
    newer = create_coding_run(job, workbook, version_number: 2, status: "processed")
    queued = create_coding_run(job, workbook, version_number: 3, status: "queued")

    queued.reference_file.attach(
      io: StringIO.new("Description,Category,Amount,GST\nSynthetic cafe,Meals,-110,-10\n"),
      filename: "synthetic-prior-quarter.csv",
      content_type: "text/csv"
    )
    queued.source_filename = nil
    queued.save!

    assert_equal [], older.original_headers
    assert_equal({}, older.column_mapping)
    assert_equal [], older.processing_errors
    assert_equal({}, older.metadata)
    assert older.processed?
    assert older.terminal_status?
    assert_not older.active_processed?
    assert newer.active_processed?
    assert queued.queued?
    assert_includes BasTdkCodingRun.running, queued
    assert_equal [ newer.id, older.id ], workbook.coding_runs.active_processed.pluck(:id)
    assert_equal "synthetic-prior-quarter.csv", queued.source_filename
    assert queued.reference_file.attached?
    assert_includes job.tdk_coding_runs, queued
  end

  test "coding run validates ownership allowlists counts rows and JSON shapes" do
    job = create_job
    other_job = create_job(legal_name: "Other Synthetic Coding Client Pty Ltd")
    run = BasTdkCodingRun.new(
      bas_job: job,
      target_workbook: create_workbook(other_job, version_number: 1),
      version_number: 0,
      status: "complete",
      header_row_number: 3,
      data_start_row: 3,
      reference_row_count: -1,
      row_count: -1,
      suggestion_count: -1,
      warning_count: -1,
      reviewed_count: -1,
      original_headers: {},
      column_mapping: [],
      row_errors: {},
      metadata: []
    )

    assert_not run.valid?
    assert_includes run.errors[:target_workbook], "must belong to the same BAS job"
    assert_equal :inclusion, run.errors.details[:status].first.fetch(:error)
    assert_equal :greater_than, run.errors.details[:version_number].first.fetch(:error)
    BasTdkCodingRun::COUNT_ATTRIBUTES.each do |attribute|
      assert_equal :greater_than_or_equal_to, run.errors.details[attribute].first.fetch(:error)
    end
    assert_includes run.errors[:data_start_row], "must be after the header row"
    assert_includes run.errors[:original_headers], "must be a JSON array"
    assert_includes run.errors[:column_mapping], "must be a JSON object"
    assert_includes run.errors[:row_errors], "must be a JSON array"
    assert_includes run.errors[:metadata], "must be a JSON object"
  end

  test "coding run version is unique within a target workbook" do
    job = create_job
    first_workbook = create_workbook(job, version_number: 1)
    second_workbook = create_workbook(job, version_number: 2)
    create_coding_run(job, first_workbook, version_number: 1)

    duplicate = BasTdkCodingRun.new(
      bas_job: job,
      target_workbook: first_workbook,
      version_number: 1
    )
    same_version_other_workbook = BasTdkCodingRun.new(
      bas_job: job,
      target_workbook: second_workbook,
      version_number: 1
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:version_number], "has already been taken"
    assert same_version_other_workbook.valid?, same_version_other_workbook.errors.full_messages.to_sentence
  end

  test "coding run summary counts cannot exceed its row count" do
    job = create_job
    workbook = create_workbook(job, version_number: 1)
    build_run = lambda do |attributes = {}|
      BasTdkCodingRun.new({
        bas_job: job,
        target_workbook: workbook,
        version_number: 1,
        status: "queued",
        row_count: 4,
        suggestion_count: 4,
        warning_count: 2,
        reviewed_count: 2
      }.merge(attributes))
    end

    assert build_run.call.valid?
    assert build_run.call(row_count: 0, suggestion_count: 0, warning_count: 0, reviewed_count: 0).valid?
    assert build_run.call(status: "processed", row_count: 0, suggestion_count: 0, warning_count: 0, reviewed_count: 0).valid?

    %i[suggestion_count warning_count reviewed_count].each do |attribute|
      run = build_run.call(row_count: 2, suggestion_count: 0, warning_count: 0, reviewed_count: 0, attribute => 3)

      assert_not run.valid?
      assert_includes run.errors[attribute], "cannot exceed row count"
    end

    combined = build_run.call(row_count: 4, suggestion_count: 4, warning_count: 2, reviewed_count: 3)

    assert_not combined.valid?
    assert_includes combined.errors[:warning_count], "and reviewed count together cannot exceed row count"
  end

  test "row coding stores independent field provenance warnings and review state" do
    job = create_job
    workbook = create_workbook(job, version_number: 1)
    row = create_row(workbook, position: 1)
    run = create_coding_run(job, workbook, version_number: 1)
    coding = BasTdkRowCoding.create!(
      coding_run: run,
      workbook_row: row,
      suggested_category: "Meals",
      suggested_gst_amount: BigDecimal("10.00"),
      gst_treatment: "taxable",
      category_source: "previous_quarter_exact",
      gst_source: "rule",
      category_confidence: BigDecimal("98.50"),
      gst_confidence: BigDecimal("65.00"),
      category_review_required: false,
      gst_review_required: true,
      review_status: "needs_review",
      warning_codes: [ "rule_gst_requires_review" ],
      explanation: "Category matched prior quarter; GST came from a rule.",
      reference_source_row_number: 12,
      reference_snapshot: { "description" => "SYNTHETIC CAFE", "gst" => "10.00" },
      metadata: { "match_score" => "0.985" }
    )

    assert_equal run, coding.coding_run
    assert_equal row, coding.workbook_row
    assert_equal BigDecimal("98.50"), coding.category_confidence
    assert_equal BigDecimal("65.00"), coding.gst_confidence
    assert coding.warning?
    assert coding.review_required?
    assert_not coding.reviewed?
    assert_includes run.row_codings, coding
    assert_includes row.row_codings, coding
    assert_includes BasTdkRowCoding.requiring_review, coding
    assert_includes BasTdkRowCoding.from_rules, coding
  end

  test "row coding validates ownership uniqueness allowlists confidence and JSON shapes" do
    job = create_job
    workbook = create_workbook(job, version_number: 1)
    other_workbook = create_workbook(job, version_number: 2)
    row = create_row(workbook, position: 1)
    other_row = create_row(other_workbook, position: 1)
    run = create_coding_run(job, workbook, version_number: 1)
    create_row_coding(run, row)

    coding = BasTdkRowCoding.new(
      coding_run: run,
      workbook_row: other_row,
      gst_treatment: "maybe_taxable",
      category_source: "ai_guess",
      gst_source: "copied",
      category_confidence: BigDecimal("-0.01"),
      gst_confidence: BigDecimal("100.01"),
      category_review_required: nil,
      gst_review_required: nil,
      review_status: "done",
      reference_source_row_number: 0,
      warning_codes: {},
      reference_snapshot: [],
      metadata: []
    )

    assert_not coding.valid?
    assert_includes coding.errors[:workbook_row], "must belong to the coding run target workbook"
    assert_equal :inclusion, coding.errors.details[:gst_treatment].first.fetch(:error)
    assert_equal :inclusion, coding.errors.details[:category_source].first.fetch(:error)
    assert_equal :inclusion, coding.errors.details[:gst_source].first.fetch(:error)
    assert_equal :greater_than_or_equal_to, coding.errors.details[:category_confidence].first.fetch(:error)
    assert_equal :less_than_or_equal_to, coding.errors.details[:gst_confidence].first.fetch(:error)
    assert_equal 2, coding.errors.details[:category_review_required].count + coding.errors.details[:gst_review_required].count
    assert_equal :inclusion, coding.errors.details[:review_status].first.fetch(:error)
    assert_equal :greater_than, coding.errors.details[:reference_source_row_number].first.fetch(:error)
    assert_includes coding.errors[:warning_codes], "must be a JSON array"
    assert_includes coding.errors[:reference_snapshot], "must be a JSON object"
    assert_includes coding.errors[:metadata], "must be a JSON object"
  end

  test "row coding is unique per run and workbook row but reusable across runs" do
    job = create_job
    workbook = create_workbook(job, version_number: 1)
    row = create_row(workbook, position: 1)
    first_run = create_coding_run(job, workbook, version_number: 1)
    second_run = create_coding_run(job, workbook, version_number: 2)
    create_row_coding(first_run, row)

    duplicate = BasTdkRowCoding.new(coding_run: first_run, workbook_row: row)
    next_run_coding = BasTdkRowCoding.new(coding_run: second_run, workbook_row: row)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:workbook_row], "already has coding for this run"
    assert next_run_coding.valid?, next_run_coding.errors.full_messages.to_sentence
  end

  test "reviewed coding requires actor and timestamp and exposes reviewed scope" do
    job = create_job
    workbook = create_workbook(job, version_number: 1)
    row = create_row(workbook, position: 1)
    run = create_coding_run(job, workbook, version_number: 1)
    coding = BasTdkRowCoding.new(
      coding_run: run,
      workbook_row: row,
      review_status: "accepted",
      category_review_required: false,
      gst_review_required: false
    )

    assert_not coding.valid?
    assert_includes coding.errors[:reviewed_by], "must be present for reviewed coding"
    assert_includes coding.errors[:reviewed_at], "must be present for reviewed coding"

    coding.reviewed_by = "synthetic-reviewer"
    coding.reviewed_at = Time.current
    coding.save!

    assert coding.reviewed?
    assert_not coding.review_required?
    assert_includes BasTdkRowCoding.reviewed, coding
  end

  test "review state agrees with review flags and reviewer details" do
    job = create_job
    workbook = create_workbook(job, version_number: 1)
    row = create_row(workbook, position: 1)
    run = create_coding_run(job, workbook, version_number: 1)
    build_coding = lambda do |attributes = {}|
      BasTdkRowCoding.new({
        coding_run: run,
        workbook_row: row,
        gst_treatment: "unknown",
        category_source: "previous_quarter_exact",
        gst_source: "previous_quarter_exact",
        category_review_required: false,
        gst_review_required: false,
        review_status: "proposed"
      }.merge(attributes))
    end

    exact_history = build_coding.call
    assert exact_history.valid?, exact_history.errors.full_messages.to_sentence

    flagged_proposal = build_coding.call(category_review_required: true)
    assert_not flagged_proposal.valid?
    assert_includes flagged_proposal.errors[:category_review_required], "must be false for an unflagged proposal"

    missing_review_flag = build_coding.call(review_status: "needs_review")
    assert_not missing_review_flag.valid?
    assert_includes missing_review_flag.errors[:review_status], "requires at least one field to need review"

    pending_review = build_coding.call(review_status: "needs_review", category_review_required: true)
    assert pending_review.valid?, pending_review.errors.full_messages.to_sentence

    pending_with_reviewer = build_coding.call(
      review_status: "needs_review",
      category_review_required: true,
      reviewed_by: "synthetic-reviewer",
      reviewed_at: Time.current
    )
    assert_not pending_with_reviewer.valid?
    assert_includes pending_with_reviewer.errors[:review_status], "must be accepted or edited when review details are recorded"

    BasTdkRowCoding::REVIEWED_STATUS_VALUES.each do |review_status|
      reviewed = build_coding.call(
        review_status: review_status,
        category_review_required: true,
        reviewed_by: "synthetic-reviewer",
        reviewed_at: Time.current
      )

      assert_not reviewed.valid?
      assert_includes reviewed.errors[:category_review_required], "must be false for reviewed coding"

      reviewed.category_review_required = false
      assert reviewed.valid?, reviewed.errors.full_messages.to_sentence
    end
  end

  test "GST treatment agrees with the suggested GST amount" do
    job = create_job
    workbook = create_workbook(job, version_number: 1)
    row = create_row(workbook, position: 1)
    run = create_coding_run(job, workbook, version_number: 1)
    build_coding = lambda do |gst_treatment, suggested_gst_amount|
      BasTdkRowCoding.new(
        coding_run: run,
        workbook_row: row,
        gst_treatment: gst_treatment,
        suggested_gst_amount: suggested_gst_amount,
        category_source: "unmatched",
        gst_source: "unmatched",
        category_review_required: false,
        gst_review_required: false,
        review_status: "proposed"
      )
    end

    BasTdkRowCoding::ZERO_GST_TREATMENT_VALUES.each do |gst_treatment|
      zero = build_coding.call(gst_treatment, BigDecimal("0"))
      missing = build_coding.call(gst_treatment, nil)
      nonzero = build_coding.call(gst_treatment, BigDecimal("-0.01"))

      assert zero.valid?, zero.errors.full_messages.to_sentence
      assert_not missing.valid?
      assert_not nonzero.valid?
      assert_includes missing.errors[:suggested_gst_amount], "must be zero for #{gst_treatment} treatment"
      assert_includes nonzero.errors[:suggested_gst_amount], "must be zero for #{gst_treatment} treatment"
    end

    [ BigDecimal("-10"), BigDecimal("0"), BigDecimal("10") ].each do |amount|
      taxable = build_coding.call("taxable", amount)
      assert taxable.valid?, taxable.errors.full_messages.to_sentence
    end

    taxable_without_amount = build_coding.call("taxable", nil)
    assert_not taxable_without_amount.valid?
    assert_includes taxable_without_amount.errors[:suggested_gst_amount], "must be present for taxable treatment"

    BasTdkRowCoding::NIL_GST_TREATMENT_VALUES.each do |gst_treatment|
      blank = build_coding.call(gst_treatment, nil)
      zero = build_coding.call(gst_treatment, BigDecimal("0"))

      assert blank.valid?, blank.errors.full_messages.to_sentence
      assert_not zero.valid?
      assert_includes zero.errors[:suggested_gst_amount], "must be blank for #{gst_treatment} treatment"
    end
  end

  test "destroying a target workbook removes its coding runs and row coding records" do
    job = create_job
    workbook = create_workbook(job, version_number: 1)
    row = create_row(workbook, position: 1)
    run = create_coding_run(job, workbook, version_number: 1)
    coding = create_row_coding(run, row)

    assert_difference "BasTdkCodingRun.count", -1 do
      assert_difference "BasTdkRowCoding.count", -1 do
        workbook.destroy!
      end
    end

    assert_not BasTdkCodingRun.exists?(run.id)
    assert_not BasTdkRowCoding.exists?(coding.id)
  end

  private

  def create_job(legal_name: "Synthetic Coding Client Pty Ltd")
    BasJob.create!(
      bas_client: BasClient.create!(legal_name: legal_name),
      period_start: Date.new(2026, 4, 1),
      period_end: Date.new(2026, 6, 30),
      workflow_type: "tdk_group",
      gst_basis: "accrual",
      reporting_method: "simpler_bas"
    )
  end

  def create_workbook(job, version_number:)
    job.tdk_workbooks.create!(
      version_number: version_number,
      status: "processed",
      source_filename: "synthetic-current-quarter-v#{version_number}.csv",
      processed_headers: %w[Date Category Amount GST Description],
      processed_at: Time.current
    )
  end

  def create_row(workbook, position:)
    workbook.rows.create!(
      position: position,
      source_row_number: position + 1,
      row_data: {
        "Date" => "2026-06-30",
        "Category" => "",
        "Amount" => "-110.00",
        "GST" => "",
        "Description" => "Synthetic cafe #{position}"
      }
    )
  end

  def create_coding_run(job, workbook, attributes = {})
    job.tdk_coding_runs.create!({
      target_workbook: workbook,
      version_number: 1,
      status: "queued"
    }.merge(attributes))
  end

  def create_row_coding(run, row, attributes = {})
    run.row_codings.create!({
      workbook_row: row,
      gst_treatment: "unknown",
      category_source: "unmatched",
      gst_source: "unmatched",
      review_status: "needs_review"
    }.merge(attributes))
  end
end
