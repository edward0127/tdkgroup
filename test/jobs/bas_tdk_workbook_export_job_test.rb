require "test_helper"
require_relative "../support/tdk_workbook_helper"

class BasTdkWorkbookExportJobTest < ActiveJob::TestCase
  include TdkWorkbookHelper

  test "export job attaches generated XLSX file for active processed workbook" do
    job = create_job
    workbook = create_processed_workbook(job)
    workbook.update!(export_status: "queued")

    BasTdkWorkbookExportJob.perform_now(workbook_id: workbook.id, actor_username: "export-job-test")

    workbook.reload
    assert_equal "processed", workbook.export_status
    assert workbook.export_file.attached?
    rows = tdk_downloaded_table_rows(workbook.export_file.download)
    assert_equal [ "Date", "Category", "Amount", "GST", "Description" ], rows.first.first(5)
    assert_equal "Meals", rows.second[1]
    assert_equal "Edited before export", rows.second[4]
  end

  test "export job ignores superseded workbook" do
    job = create_job
    superseded = create_processed_workbook(job, version_number: 1, status: "superseded")
    create_processed_workbook(job, version_number: 2, description: "Active row")
    superseded.update!(export_status: "queued")

    BasTdkWorkbookExportJob.perform_now(workbook_id: superseded.id, actor_username: "export-job-test")

    assert_equal "queued", superseded.reload.export_status
    assert_not superseded.export_file.attached?
  end

  test "running export leaves workbook stale if rows are edited during generation" do
    job = create_job
    workbook = create_processed_workbook(job)
    workbook.update!(export_status: "queued")

    original_new = BasTdk::WorkbookExporter.method(:new)
    BasTdk::WorkbookExporter.define_singleton_method(:new) do |workbook:|
      workbook.invalidate_export!
      BasTdk::WorkbookExporter.allocate.tap do |exporter|
        exporter.define_singleton_method(:call) { "not a real xlsx" }
      end
    end

    begin
      BasTdkWorkbookExportJob.perform_now(workbook_id: workbook.id, actor_username: "export-job-test")
    ensure
      BasTdk::WorkbookExporter.define_singleton_method(:new, original_new)
    end

    assert_equal "stale", workbook.reload.export_status
    assert_not workbook.export_file.attached?
  end

  private

  def create_job
    BasJob.create!(
      bas_client: BasClient.create!(legal_name: "Synthetic Export Job Client Pty Ltd"),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      workflow_type: "tdk_group"
    )
  end

  def create_processed_workbook(job, version_number: 1, status: "processed", description: "Edited before export")
    workbook = job.tdk_workbooks.create!(
      status: status,
      source_filename: "synthetic-export.xlsx",
      sheet_name: "Bank Report",
      header_row_number: 1,
      original_headers: [ "Date", "Amount", "Description" ],
      processed_headers: [ "Date", "Category", "Amount", "GST", "Description" ],
      row_count: 1,
      version_number: version_number,
      processed_at: Time.current,
      processed_by: "export-job-test"
    )
    workbook.rows.create!(
      position: 1,
      source_row_number: 2,
      row_data: {
        "Date" => "2026-01-05",
        "Category" => "Meals",
        "Amount" => "100.00",
        "GST" => "GST included",
        "Description" => description
      }
    )
    workbook
  end
end
