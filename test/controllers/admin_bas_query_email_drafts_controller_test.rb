require "test_helper"

class AdminBasQueryEmailDraftsControllerTest < ActionDispatch::IntegrationTest
  setup do
    login_as_admin
  end

  test "non-admin cannot access query email draft page" do
    job = bas_job

    reset!

    get admin_bas_job_query_email_draft_path(job)
    assert_redirected_to admin_login_path

    post mark_waiting_for_client_admin_bas_job_query_email_draft_path(job)
    assert_redirected_to admin_login_path
  end

  test "admin can view query email draft" do
    job = bas_job
    query(job, title: "Missing client receipt", details: "Please provide the January receipt.")

    assert_difference -> { BasAuditEvent.where(event_type: "bas_query_email_draft_generated").count }, 1 do
      get admin_bas_job_query_email_draft_path(job)
    end

    assert_response :success
    assert_select "input#email_draft_to[value=?]", "client@example.test"
    assert_select "input#email_draft_subject[value=?]", "BAS information required - Synthetic Email Draft Client Pty Ltd - #{job.period_label}"
    assert_select "textarea#email_draft_body", /Missing client receipt/
    assert_select "p", text: "Please review before sending. This system does not send emails automatically."
  end

  test "admin can see subject and body without automatic email controls" do
    job = bas_job
    query(job, title: "Confirm GST", query_type: "gst_treatment_unclear")

    get admin_bas_job_query_email_draft_path(job)

    assert_response :success
    assert_includes response.body, "Copy subject"
    assert_includes response.body, "Copy body"
    assert_includes response.body, "GST treatment to confirm"
    assert_not_includes response.body, "mailto:"
  end

  test "admin can mark included open queries as waiting for client" do
    job = bas_job
    open_query = query(job, title: "Open query")
    waiting_query = query(job, title: "Already waiting", status: "waiting_for_client")

    assert_difference -> { BasAuditEvent.where(event_type: "bas_queries_marked_waiting_for_client").count }, 1 do
      post mark_waiting_for_client_admin_bas_job_query_email_draft_path(job)
    end

    assert_redirected_to admin_bas_job_query_email_draft_path(job)
    assert_equal "waiting_for_client", open_query.reload.status
    assert_equal "waiting_for_client", waiting_query.reload.status

    event = BasAuditEvent.where(event_type: "bas_queries_marked_waiting_for_client").last
    assert_equal [ open_query.id ], event.metadata.fetch("query_ids")
    assert_equal 1, event.metadata.fetch("query_count")
    assert_not event.metadata.key?("email_body")
  end

  test "locked job blocks status-changing action" do
    job = bas_job(status: "locked")
    open_query = query(job, title: "Locked query")

    assert_no_difference -> { BasAuditEvent.where(event_type: "bas_queries_marked_waiting_for_client").count } do
      post mark_waiting_for_client_admin_bas_job_query_email_draft_path(job)
    end

    assert_redirected_to admin_bas_job_query_email_draft_path(job)
    assert_equal "open", open_query.reload.status
  end

  test "show creates safe generated audit event metadata" do
    job = bas_job
    included_query = query(job, title: "Audit-safe query")

    get admin_bas_job_query_email_draft_path(job)

    event = BasAuditEvent.where(event_type: "bas_query_email_draft_generated").last
    assert_equal job.id, event.bas_job_id
    assert_equal job.id, event.metadata.fetch("bas_job_id")
    assert_equal job.bas_client_id, event.metadata.fetch("bas_client_id")
    assert_equal [ included_query.id ], event.metadata.fetch("query_ids")
    assert_equal 1, event.metadata.fetch("query_count")
    assert_not event.metadata.key?("email_body")
    assert_not event.metadata.key?("raw_document_contents")
  end

  private

  def login_as_admin
    with_modified_env("ADMIN_USERNAME" => "query-email-admin", "ADMIN_PASSWORD" => "secret-password") do
      post admin_login_path, params: { username: "query-email-admin", password: "secret-password" }
      assert_redirected_to admin_root_path
    end
  end

  def bas_job(attributes = {})
    client = BasClient.create!(
      legal_name: "Synthetic Email Draft Client Pty Ltd",
      contact_name: "Client Contact",
      contact_email: "client@example.test",
      default_gst_basis: "accrual",
      default_reporting_method: "simpler_bas"
    )
    BasJob.create!({
      bas_client: client,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      gst_basis: "accrual",
      reporting_method: "simpler_bas"
    }.merge(attributes))
  end

  def query(job, attributes = {})
    job.queries.create!({
      title: "Synthetic client query",
      query_type: "missing_receipt",
      status: "open",
      details: "Synthetic client-safe details.",
      created_by: "query-email-admin",
      updated_by: "query-email-admin"
    }.merge(attributes))
  end
end
