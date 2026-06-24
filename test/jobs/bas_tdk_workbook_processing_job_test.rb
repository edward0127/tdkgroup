require "test_helper"
require_relative "../support/tdk_workbook_helper"

class BasTdkWorkbookProcessingJobTest < ActiveJob::TestCase
  include TdkWorkbookHelper

  test "processing job marks workbook processed and creates rows" do
    job = create_job
    workbook = create_queued_workbook(job, tdk_xlsx_upload(workbook_rows))

    BasTdkWorkbookProcessingJob.perform_now(workbook_id: workbook.id, actor_username: "job-test")

    workbook.reload
    assert_equal "processed", workbook.status
    assert workbook.processing_started_at.present?
    assert workbook.processing_finished_at.present?
    assert_equal 2, workbook.rows.count
    assert_equal [ "Date", "Category", "Amount", "GST", "Description" ], workbook.processed_headers
    assert_equal "Synthetic cafe sale", workbook.rows.ordered.first.row_data.fetch("Description")
    assert_equal "bas_tdk_workbook_processing_completed", BasAuditEvent.recent.first.event_type
  end

  test "successful processing supersedes previous processed workbook only after success" do
    job = create_job
    previous = create_processed_workbook(job, version_number: 1)
    workbook = create_queued_workbook(job, tdk_xlsx_upload(workbook_rows), version_number: 2)

    BasTdkWorkbookProcessingJob.perform_now(workbook_id: workbook.id, actor_username: "job-test")

    assert_equal "superseded", previous.reload.status
    assert_equal "processed", workbook.reload.status
    assert_equal workbook.id, job.tdk_workbooks.active_processed.first.id
  end

  test "failed processing keeps previous processed workbook active" do
    job = create_job
    previous = create_processed_workbook(job, version_number: 1)
    workbook = create_queued_workbook(
      job,
      tdk_xlsx_upload([
        [ "Synthetic Business Pty Ltd" ],
        [ "No transaction table here" ]
      ]),
      version_number: 2
    )

    BasTdkWorkbookProcessingJob.perform_now(workbook_id: workbook.id, actor_username: "job-test")

    workbook.reload
    assert_equal "failed", workbook.status
    assert_includes workbook.processing_errors, BasTdk::WorkbookProcessor::FRIENDLY_HEADER_ERROR
    assert_equal "processed", previous.reload.status
    assert_equal previous.id, job.tdk_workbooks.active_processed.first.id
    assert_equal 1, previous.rows.count
  end

  test "duplicate processing job does not process non queued workbook again" do
    job = create_job
    workbook = create_queued_workbook(job, tdk_xlsx_upload(workbook_rows))

    BasTdkWorkbookProcessingJob.perform_now(workbook_id: workbook.id, actor_username: "job-test")
    assert_no_difference "BasTdkWorkbookRow.count" do
      BasTdkWorkbookProcessingJob.perform_now(workbook_id: workbook.id, actor_username: "job-test")
    end

    assert_equal "processed", workbook.reload.status
  end

  private

  def create_job
    BasJob.create!(
      bas_client: BasClient.create!(legal_name: "Synthetic Processing Job Client Pty Ltd"),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      workflow_type: "tdk_group"
    )
  end

  def create_queued_workbook(job, upload, version_number: 1)
    workbook = job.tdk_workbooks.create!(
      status: "queued",
      source_filename: upload.original_filename,
      version_number: version_number,
      processed_by: "job-test"
    )
    workbook.source_file.attach(upload)
    workbook
  end

  def create_processed_workbook(job, version_number:)
    workbook = job.tdk_workbooks.create!(
      status: "processed",
      source_filename: "previous.xlsx",
      sheet_name: "Bank Report",
      header_row_number: 1,
      original_headers: [ "Date", "Amount", "Description" ],
      processed_headers: [ "Date", "Category", "Amount", "GST", "Description" ],
      row_count: 1,
      version_number: version_number,
      processed_at: Time.current,
      processed_by: "job-test"
    )
    workbook.rows.create!(
      position: 1,
      source_row_number: 2,
      row_data: {
        "Date" => "2026-01-01",
        "Category" => "Existing",
        "Amount" => "10.00",
        "GST" => "GST included",
        "Description" => "Existing active row"
      }
    )
    workbook
  end

  def workbook_rows
    [
      [ "Synthetic Business Pty Ltd" ],
      [],
      [ "Date", "Amount", "Description" ],
      [ Date.new(2026, 1, 5), "123.45", "Synthetic cafe sale" ],
      [ Date.new(2026, 1, 6), "-67.89", "Synthetic supplier payment" ]
    ]
  end
end
