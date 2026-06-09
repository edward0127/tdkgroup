require "test_helper"

class AdminBasReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    login_as_admin
  end

  test "non-admin cannot access BAS report pages or actions" do
    job = clean_matched_job
    snapshot = BasReports::SnapshotBuilder.new(bas_job: job, actor_username: "phase4-admin").create_draft!

    reset!

    get admin_bas_job_report_path(job)
    assert_redirected_to admin_login_path

    post calculate_admin_bas_job_report_path(job)
    assert_redirected_to admin_login_path

    get download_summary_csv_admin_bas_job_report_snapshot_path(job, snapshot)
    assert_redirected_to admin_login_path
  end

  test "admin can view report page and calculate draft report" do
    job = clean_matched_job

    get admin_bas_job_report_path(job)
    assert_response :success
    assert_select "h1", "Report & snapshots"
    assert_includes response.body, "Client: #{job.bas_client.primary_name}"

    assert_difference "BasReportSnapshot.count", 1 do
      assert_difference "BasAuditEvent.count", 2 do
        post calculate_admin_bas_job_report_path(job)
      end
    end

    snapshot = BasReportSnapshot.last
    assert_redirected_to admin_bas_job_report_snapshot_path(job, snapshot)
    assert_equal "draft", snapshot.status
    assert_equal "110.00", snapshot.totals.fetch("summary").fetch("g1_total_sales")
    assert_equal "report_ready", job.reload.status
    assert_equal "phase4-admin", snapshot.generated_by
  end

  test "report mutation forms include visible submit guard loading text" do
    job = clean_matched_job

    get admin_bas_job_report_path(job)

    assert_response :success
    assert_guarded_form calculate_admin_bas_job_report_path(job), "Calculating"

    snapshot = BasReports::SnapshotBuilder.new(bas_job: job, actor_username: "phase4-admin").create_draft!

    get admin_bas_job_report_snapshot_path(job, snapshot)

    assert_response :success
    assert_guarded_form approve_admin_bas_job_report_snapshot_path(job, snapshot), "Approving"
    assert_select "form[action='#{approve_admin_bas_job_report_snapshot_path(job, snapshot)}'][data-turbo-confirm]"

    snapshot.update!(status: "final", approved_at: Time.current, approved_by: "phase4-admin")
    job.update!(status: "approved")

    get admin_bas_job_report_snapshot_path(job, snapshot)

    assert_response :success
    assert_guarded_form lock_admin_bas_job_report_snapshot_path(job, snapshot), "Locking"
    assert_select "form[action='#{lock_admin_bas_job_report_snapshot_path(job, snapshot)}'][data-turbo-confirm]"
  end

  test "admin can add adjustment with audit actor" do
    job = bas_job

    assert_difference "BasAdjustment.count", 1 do
      assert_difference "BasAuditEvent.count", 1 do
        post admin_bas_job_adjustments_path(job), params: {
          bas_adjustment: {
            adjustment_type: "gst_on_sales",
            label: "Synthetic GST adjustment",
            amount: "7.00",
            reason: "Synthetic review reason"
          }
        }
      end
    end

    adjustment = BasAdjustment.last
    assert_redirected_to admin_bas_job_report_path(job)
    assert_equal "phase4-admin", adjustment.created_by
    assert_equal "bas_adjustment_created", BasAuditEvent.last.event_type
    assert_equal "phase4-admin", BasAuditEvent.last.actor_username
  end

  test "admin cannot approve snapshot with blockers" do
    job = bas_job
    BasQuery.create!(bas_job: job, title: "Synthetic open query")
    snapshot = BasReports::SnapshotBuilder.new(bas_job: job, actor_username: "phase4-admin").create_draft!

    assert_no_changes -> { snapshot.reload.status } do
      patch approve_admin_bas_job_report_snapshot_path(job, snapshot)
    end

    assert_redirected_to admin_bas_job_report_snapshot_path(job, snapshot)
    assert_equal "draft", snapshot.reload.status
  end

  test "admin can approve clean final snapshot and lock approved job" do
    job = clean_matched_job
    snapshot = BasReports::SnapshotBuilder.new(bas_job: job, actor_username: "phase4-admin").create_draft!

    assert_difference "BasAuditEvent.count", 1 do
      patch approve_admin_bas_job_report_snapshot_path(job, snapshot)
    end

    assert_redirected_to admin_bas_job_report_snapshot_path(job, snapshot)
    assert_equal "final", snapshot.reload.status
    assert_equal "approved", job.reload.status
    assert_equal "phase4-admin", snapshot.approved_by
    assert_equal "bas_report_approved", BasAuditEvent.last.event_type

    assert_difference "BasAuditEvent.count", 1 do
      patch lock_admin_bas_job_report_snapshot_path(job, snapshot)
    end

    assert_redirected_to admin_bas_job_report_snapshot_path(job, snapshot)
    assert_equal "locked", job.reload.status
    assert_equal "phase4-admin", job.locked_by
    assert_equal "phase4-admin", snapshot.reload.locked_by
    assert_equal "bas_job_locked", BasAuditEvent.last.event_type
  end

  test "locked job blocks report-changing actions" do
    job = bas_job(status: "locked", locked_at: Time.current, locked_by: "phase4-admin")

    assert_no_difference "BasReportSnapshot.count" do
      post calculate_admin_bas_job_report_path(job)
    end
    assert_redirected_to admin_bas_job_report_path(job)

    assert_no_difference "BasAdjustment.count" do
      post admin_bas_job_adjustments_path(job), params: {
        bas_adjustment: {
          adjustment_type: "gst_on_sales",
          label: "Locked adjustment",
          amount: "1.00",
          reason: "Synthetic reason"
        }
      }
    end
    assert_redirected_to admin_bas_job_report_path(job)
  end

  test "admin can download CSV exports and view printable report" do
    job = clean_matched_job
    snapshot = BasReports::SnapshotBuilder.new(bas_job: job, actor_username: "phase4-admin").create_draft!

    get download_summary_csv_admin_bas_job_report_snapshot_path(job, snapshot)
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.body, "G1 total sales"

    get download_gst_detail_csv_admin_bas_job_report_snapshot_path(job, snapshot)
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.body, "Synthetic Customer"

    get download_matches_csv_admin_bas_job_report_snapshot_path(job, snapshot)
    assert_response :success
    assert_includes response.body, "invoice_to_bank_transaction"

    get download_queries_csv_admin_bas_job_report_snapshot_path(job, snapshot)
    assert_response :success
    assert_includes response.body, "Query ID"

    get print_admin_bas_job_report_snapshot_path(job, snapshot)
    assert_response :success
    assert_select "h1", "Printable BAS report"
    assert_includes response.body, "Client: #{job.bas_client.primary_name}"
  end

  private

  def login_as_admin
    with_modified_env("ADMIN_USERNAME" => "phase4-admin", "ADMIN_PASSWORD" => "secret-password") do
      post admin_login_path, params: { username: "phase4-admin", password: "secret-password" }
      assert_redirected_to admin_root_path
    end
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
    invoice_record = BasInvoice.create!(
      bas_job: job,
      direction: "sale",
      invoice_number: "INV-001",
      issue_date: Date.new(2026, 1, 15),
      party_name: "Synthetic Customer",
      total_amount: BigDecimal("110.00"),
      gst_amount: BigDecimal("10.00"),
      payment_method: "bank",
      gst_code: "taxable",
      status: "matched"
    )
    bank_record = BasBankTransaction.create!(
      bas_job: job,
      transaction_date: Date.new(2026, 1, 20),
      description: "Synthetic Customer payment",
      amount: BigDecimal("110.00"),
      status: "matched"
    )
    match = BasMatch.create!(
      bas_job: job,
      match_type: "invoice_to_bank_transaction",
      status: "accepted",
      matched_amount: BigDecimal("110.00"),
      accepted_at: Time.current,
      accepted_by: "phase4-admin"
    )
    match.items.create!(matchable: invoice_record, amount: invoice_record.total_amount)
    match.items.create!(matchable: bank_record, amount: bank_record.amount)
    job
  end

  def assert_guarded_form(action, loading_text)
    form = Nokogiri::HTML(response.body).at_css("form[action='#{action}'][data-controller='submit-guard'][data-submit-guard-loading-text-value='#{loading_text}']")

    assert form, "Expected guarded form #{action} with loading text #{loading_text.inspect}"
    assert_includes form["data-action"], "turbo:submit-start->submit-guard#submitStart"
    assert_includes form["data-action"], "turbo:submit-end->submit-guard#submitEnd"
  end
end
