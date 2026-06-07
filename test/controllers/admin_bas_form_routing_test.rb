require "test_helper"
require "rack/test"

class AdminBasFormRoutingTest < ActionDispatch::IntegrationTest
  setup do
    login_as_admin
  end

  test "new client form posts to BAS clients path" do
    get new_admin_bas_client_path

    assert_response :success
    assert_form_posts_to admin_bas_clients_path
  end

  test "edit client form patches to BAS client path" do
    client = create_client

    get edit_admin_bas_client_path(client)

    assert_response :success
    assert_form_patches_to admin_bas_client_path(client)
  end

  test "new job form posts to BAS jobs path" do
    create_client

    get new_admin_bas_job_path

    assert_response :success
    assert_form_posts_to admin_bas_jobs_path
  end

  test "edit job form patches to BAS job path" do
    job = create_job

    get edit_admin_bas_job_path(job)

    assert_response :success
    assert_form_patches_to admin_bas_job_path(job)
  end

  test "new document form posts to BAS job documents path" do
    job = create_job

    get new_admin_bas_job_document_path(job)

    assert_response :success
    assert_form_posts_to admin_bas_job_documents_path(job)
    assert_select "form[action=?][enctype=?]", admin_bas_job_documents_path(job), "multipart/form-data"
  end

  test "new query form posts to BAS job queries path" do
    job = create_job

    get new_admin_bas_job_query_path(job)

    assert_response :success
    assert_form_posts_to admin_bas_job_queries_path(job)
  end

  test "edit query form patches to BAS job query path" do
    job = create_job
    query = create_query(job)

    get edit_admin_bas_job_query_path(job, query)

    assert_response :success
    assert_form_patches_to admin_bas_job_query_path(job, query)
  end

  test "new adjustment form posts to BAS job adjustments path" do
    job = create_job

    get new_admin_bas_job_adjustment_path(job)

    assert_response :success
    assert_form_posts_to admin_bas_job_adjustments_path(job)
  end

  test "edit adjustment form patches to BAS job adjustment path" do
    job = create_job
    adjustment = create_adjustment(job)

    get edit_admin_bas_job_adjustment_path(job, adjustment)

    assert_response :success
    assert_form_patches_to admin_bas_job_adjustment_path(job, adjustment)
  end

  test "new import run form posts to BAS job import runs path" do
    job = create_job
    create_document(job)

    get new_admin_bas_job_import_run_path(job)

    assert_response :success
    assert_form_posts_to admin_bas_job_import_runs_path(job)
  end

  test "new manual match form posts to BAS job matches path" do
    job = create_job
    create_invoice(job)
    create_bank_transaction(job)

    get new_admin_bas_job_match_path(job)

    assert_response :success
    assert_form_posts_to admin_bas_job_matches_path(job)
  end

  private

  def assert_form_posts_to(path)
    assert_select "form[action=?][method=?]", path, "post"
  end

  def assert_form_patches_to(path)
    assert_form_posts_to path
    assert_select "form[action=?] input[name=?][value=?]", path, "_method", "patch"
  end

  def login_as_admin
    with_modified_env("ADMIN_USERNAME" => "bas-form-admin", "ADMIN_PASSWORD" => "secret-password") do
      post admin_login_path, params: { username: "bas-form-admin", password: "secret-password" }
      assert_redirected_to admin_root_path
    end
  end

  def create_client(attributes = {})
    BasClient.create!({
      legal_name: "Synthetic Form Client #{SecureRandom.hex(3)} Pty Ltd",
      trading_name: "",
      abn: "11111111111",
      contact_name: "Synthetic Contact",
      contact_email: "synthetic-form@example.test",
      contact_phone: "0400000000",
      default_gst_basis: "accrual",
      reporting_frequency: "quarterly",
      default_reporting_method: "simpler_bas",
      notes: "Synthetic form notes",
      archived: false
    }.merge(attributes))
  end

  def create_job(attributes = {})
    client = attributes.delete(:bas_client) || create_client
    BasJob.create!({
      bas_client: client,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      gst_basis: "accrual",
      reporting_method: "simpler_bas"
    }.merge(attributes))
  end

  def create_document(job)
    document = job.documents.build(title: "Synthetic form import", document_type: "bank_statement", uploaded_by: "bas-form-admin")
    document.file.attach(csv_upload)
    document.save!
    document
  end

  def create_query(job)
    job.queries.create!(
      title: "Synthetic form query",
      query_type: "missing_receipt",
      status: "open",
      details: "Synthetic details",
      created_by: "bas-form-admin",
      updated_by: "bas-form-admin"
    )
  end

  def create_adjustment(job)
    job.adjustments.create!(
      adjustment_type: "gst_on_sales",
      label: "Synthetic form adjustment",
      amount: BigDecimal("1.00"),
      reason: "Synthetic form reason",
      created_by: "bas-form-admin"
    )
  end

  def create_invoice(job)
    job.invoices.create!(
      direction: "sale",
      invoice_number: "FORM-#{SecureRandom.hex(2)}",
      issue_date: Date.new(2026, 1, 2),
      party_name: "Synthetic Form Customer",
      total_amount: BigDecimal("110.00"),
      gst_amount: BigDecimal("10.00"),
      payment_method: "bank",
      gst_code: "taxable",
      status: "imported"
    )
  end

  def create_bank_transaction(job)
    job.bank_transactions.create!(
      transaction_date: Date.new(2026, 1, 3),
      description: "Synthetic Form Customer payment",
      amount: BigDecimal("110.00"),
      status: "imported"
    )
  end

  def csv_upload
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/bas_sample.csv").to_s,
      "text/csv"
    )
  end
end
