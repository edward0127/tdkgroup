require "test_helper"
require "rack/test"

class AdminBasWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    login_as_admin
  end

  test "non admin cannot access admin BAS dashboard" do
    reset!

    get admin_bas_root_path

    assert_redirected_to admin_login_path
  end

  test "admin can access BAS dashboard" do
    get admin_bas_root_path

    assert_response :success
    assert_select "h1", "BAS workspace"
    assert_select "a[href='#{new_admin_bas_job_path(workflow_type: "tdk_group")}']", text: "New TDK BAS job"
    assert_select "a[href='#{new_admin_bas_job_path(workflow_type: "tdk_group")}']", text: "New TDK BAS"
    assert_select "a[href='#{new_admin_bas_job_path}']", text: "New standard BAS job"
  end

  test "BAS dashboard recent jobs show workflow labels" do
    client = create_client(legal_name: "Synthetic Dashboard Client Pty Ltd")
    standard_job = create_job(bas_client: client, workflow_type: "standard")
    tdk_job = create_job(bas_client: client, workflow_type: "tdk_group")

    get admin_bas_root_path

    assert_response :success
    assert_select "th", "Workflow"
    assert_select "a[href='#{admin_bas_job_path(standard_job)}']", text: standard_job.period_label
    assert_select "a[href='#{admin_bas_job_path(tdk_job)}']", text: tdk_job.period_label
    assert_select "td", text: "Standard BAS preparation"
    assert_select "td", text: "TDK Group BAS workflow"
  end

  test "admin can create and update BAS client with audit actor" do
    assert_difference "BasClient.count", 1 do
      assert_difference "BasAuditEvent.count", 1 do
        post admin_bas_clients_path, params: {
          bas_client: client_params(legal_name: "Synthetic Client One Pty Ltd")
        }
      end
    end

    client = BasClient.find_by!(legal_name: "Synthetic Client One Pty Ltd")
    assert_redirected_to admin_bas_client_path(client)
    assert_equal "bas-admin", BasAuditEvent.last.actor_username
    assert_equal "bas_client_created", BasAuditEvent.last.event_type
    assert_equal "other", client.industry

    assert_difference "BasAuditEvent.count", 1 do
      patch admin_bas_client_path(client), params: {
        bas_client: client_params(trading_name: "Synthetic Trading", industry: "medical_service")
      }
    end

    assert_redirected_to admin_bas_client_path(client)
    assert_equal "Synthetic Trading", client.reload.trading_name
    assert_equal "medical_service", client.industry
    assert_equal "bas-admin", BasAuditEvent.last.actor_username
  end

  test "admin can create and update BAS job" do
    client = create_client(default_gst_basis: "cash", default_reporting_method: "simpler_bas")

    assert_difference "BasJob.count", 1 do
      assert_difference "BasAuditEvent.count", 1 do
        post admin_bas_jobs_path, params: {
          bas_job: job_params(bas_client_id: client.id)
        }
      end
    end

    job = BasJob.last
    assert_redirected_to admin_bas_job_path(job)
    assert_equal "cash", job.gst_basis
    assert_equal "simpler_bas", job.reporting_method
    assert_equal "standard", job.workflow_type

    assert_difference "BasAuditEvent.count", 2 do
      patch admin_bas_job_path(job), params: {
        bas_job: job_params(bas_client_id: client.id, status: "collecting_materials", workflow_type: "tdk_group")
      }
    end

    assert_redirected_to admin_bas_job_path(job)
    assert_equal "collecting_materials", job.reload.status
    assert_equal "tdk_group", job.workflow_type
    assert_equal "bas_job_status_changed", BasAuditEvent.last.event_type
    assert_equal "bas-admin", BasAuditEvent.last.actor_username
  end

  test "admin can upload and download BAS document but public cannot download it" do
    job = create_job

    assert_difference "BasDocument.count", 1 do
      assert_difference "BasAuditEvent.count", 1 do
        post admin_bas_job_documents_path(job), params: {
          bas_document: {
            title: "Synthetic bank statement",
            document_type: "bank_statement",
            file: csv_upload
          }
        }
      end
    end

    document = BasDocument.last
    assert_redirected_to admin_bas_job_path(job)
    assert_equal "bas-admin", document.uploaded_by
    assert_equal "bas_document_uploaded", BasAuditEvent.last.event_type

    get download_admin_bas_job_document_path(job, document)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.headers.fetch("Content-Disposition"), "attachment"
    assert_includes response.body, "Synthetic bank item"

    reset!
    get download_admin_bas_job_document_path(job, document)

    assert_redirected_to admin_login_path
  end

  test "admin can delete BAS document unless job is locked" do
    job = create_job
    document = create_document(job)

    assert_difference "BasDocument.count", -1 do
      assert_difference "BasAuditEvent.count", 1 do
        delete admin_bas_job_document_path(job, document)
      end
    end

    assert_redirected_to admin_bas_job_path(job)
    assert_equal "bas_document_deleted", BasAuditEvent.last.event_type

    locked_job = create_job(status: "locked")
    locked_document = create_document(locked_job)

    assert_no_difference "BasDocument.count" do
      delete admin_bas_job_document_path(locked_job, locked_document)
    end

    assert_redirected_to admin_bas_job_path(locked_job)
  end

  test "admin can create and update BAS queries through workflow states" do
    job = create_job

    assert_difference "BasQuery.count", 1 do
      assert_difference "BasAuditEvent.count", 1 do
        post admin_bas_job_queries_path(job), params: {
          bas_query: query_params(title: "Synthetic missing receipt")
        }
      end
    end

    query = BasQuery.last
    assert_redirected_to admin_bas_job_path(job)
    assert_equal "bas-admin", query.created_by
    assert_equal "bas_query_created", BasAuditEvent.last.event_type

    patch admin_bas_job_query_path(job, query), params: {
      bas_query: query_params(status: "waiting_for_client")
    }

    assert_redirected_to admin_bas_job_path(job)
    assert_equal "waiting_for_client", query.reload.status

    patch admin_bas_job_query_path(job, query), params: {
      bas_query: query_params(status: "resolved", resolution_notes: "Synthetic client provided the receipt.")
    }

    assert_redirected_to admin_bas_job_path(job)
    assert_equal "resolved", query.reload.status
    assert_equal "bas_query_resolved", BasAuditEvent.last.event_type
    assert_equal "bas-admin", BasAuditEvent.last.actor_username

    dismissed_query = BasQuery.create!(
      bas_job: job,
      title: "Synthetic duplicate query",
      created_by: "bas-admin",
      updated_by: "bas-admin"
    )

    patch admin_bas_job_query_path(job, dismissed_query), params: {
      bas_query: query_params(status: "dismissed", resolution_notes: "Synthetic duplicate dismissed.")
    }

    assert_redirected_to admin_bas_job_path(job)
    assert_equal "dismissed", dismissed_query.reload.status
    assert_equal "bas_query_dismissed", BasAuditEvent.last.event_type
  end

  private

  def login_as_admin
    with_modified_env("ADMIN_USERNAME" => "bas-admin", "ADMIN_PASSWORD" => "secret-password") do
      post admin_login_path, params: { username: "bas-admin", password: "secret-password" }
      assert_redirected_to admin_root_path
    end
  end

  def client_params(attributes = {})
    {
      legal_name: "Synthetic Client Pty Ltd",
      trading_name: "",
      abn: "11111111111",
      contact_name: "Synthetic Contact",
      contact_email: "synthetic@example.test",
      contact_phone: "0400000000",
      industry: "other",
      default_gst_basis: "cash",
      reporting_frequency: "quarterly",
      default_reporting_method: "simpler_bas",
      notes: "Synthetic notes",
      archived: "0"
    }.merge(attributes)
  end

  def job_params(attributes = {})
    {
      bas_client_id: attributes.fetch(:bas_client_id),
      period_start: "2026-01-01",
      period_end: "2026-03-31",
      quarter_label: "",
      workflow_type: attributes.fetch(:workflow_type, "standard"),
      status: attributes.fetch(:status, "draft"),
      gst_basis: "unknown",
      reporting_method: "unknown",
      payroll_applicable: "1",
      cash_transactions_applicable: "0",
      internal_notes: "Synthetic internal notes"
    }.merge(attributes)
  end

  def query_params(attributes = {})
    {
      title: "Synthetic query",
      query_type: "missing_receipt",
      status: attributes.fetch(:status, "open"),
      details: "Synthetic details",
      resolution_notes: ""
    }.merge(attributes)
  end

  def create_client(attributes = {})
    BasClient.create!(client_params(attributes))
  end

  def create_job(attributes = {})
    client = attributes.delete(:bas_client) || create_client
    BasJob.create!({
      bas_client: client,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31)
    }.merge(attributes))
  end

  def create_document(job)
    document = job.documents.build(title: "Synthetic bank statement", document_type: "bank_statement", uploaded_by: "bas-admin")
    document.file.attach(csv_upload)
    document.save!
    document
  end

  def csv_upload
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/bas_sample.csv").to_s,
      "text/csv"
    )
  end
end
