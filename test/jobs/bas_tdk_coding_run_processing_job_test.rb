require "test_helper"

class BasTdkCodingRunProcessingJobTest < ActiveJob::TestCase
  test "claims a queued run processes suggestions and records terminal audits" do
    job = create_job
    workbook = create_workbook(job)
    workbook.rows.create!(
      position: 1,
      source_row_number: 2,
      row_data: { "Date" => "2026-06-30", "Category" => "", "Amount" => "-121.00", "GST" => "", "Description" => "Adobe Creative Cloud" }
    )
    run = create_run(job, workbook)

    BasTdkCodingRunProcessingJob.perform_now(coding_run_id: run.id, actor_username: "job-test")

    assert_equal "processed", run.reload.status
    assert run.processing_started_at.present?
    assert run.processing_finished_at.present?
    assert_equal "job-test", run.requested_by
    assert_equal 1, run.row_codings.count
    events = job.audit_events.where(auditable: run).order(:id).pluck(:event_type)
    assert_equal [
      "bas_tdk_coding_run_processing_started",
      "bas_tdk_coding_run_processing_completed"
    ], events
  end

  test "duplicate jobs do not reprocess a terminal run" do
    job = create_job
    workbook = create_workbook(job)
    workbook.rows.create!(
      position: 1,
      row_data: { "Category" => "", "Amount" => "-10.00", "GST" => "", "Description" => "Account fee" }
    )
    run = create_run(job, workbook)

    BasTdkCodingRunProcessingJob.perform_now(coding_run_id: run.id)
    assert_no_difference [ "BasTdkRowCoding.count", "BasAuditEvent.count" ] do
      BasTdkCodingRunProcessingJob.perform_now(coding_run_id: run.id)
    end
  end

  test "unexpected processor errors are recorded safely without exposing a technical message to the row errors" do
    job = create_job
    workbook = create_workbook(job)
    run = create_run(job, workbook)
    original_new = BasTdk::CodingRunProcessor.method(:new)
    failing = Object.new
    failing.define_singleton_method(:call) { raise "synthetic secret failure" }
    BasTdk::CodingRunProcessor.define_singleton_method(:new) { |**_kwargs| failing }

    begin
      BasTdkCodingRunProcessingJob.perform_now(coding_run_id: run.id, actor_username: "job-test")
    ensure
      BasTdk::CodingRunProcessor.define_singleton_method(:new, original_new)
    end

    assert_equal "failed", run.reload.status
    assert_includes run.processing_errors.to_sentence, "could not be completed"
    refute_includes run.processing_errors.to_sentence, "synthetic secret"
    assert_equal "RuntimeError", run.metadata.fetch("exception_class")
    assert_equal "bas_tdk_coding_run_processing_failed", job.audit_events.where(auditable: run).recent.first.event_type
  end

  private

  def create_job
    BasJob.create!(
      bas_client: BasClient.create!(legal_name: "Synthetic Coding Job #{SecureRandom.hex(4)} Pty Ltd"),
      period_start: Date.new(2026, 4, 1),
      period_end: Date.new(2026, 6, 30),
      workflow_type: "tdk_group"
    )
  end

  def create_workbook(job)
    job.tdk_workbooks.create!(
      version_number: 1,
      status: "processed",
      source_filename: "current.csv",
      processed_headers: %w[Date Category Amount GST Description],
      processed_at: Time.current
    )
  end

  def create_run(job, workbook)
    run = job.tdk_coding_runs.create!(target_workbook: workbook, version_number: 1, status: "queued")
    run.reference_file.attach(
      io: StringIO.new("Description,Category,Amount,GST\nAdobe Creative Cloud,Software,-121.00,-11.00\n"),
      filename: "prior-quarter.csv",
      content_type: "text/csv"
    )
    run
  end
end
