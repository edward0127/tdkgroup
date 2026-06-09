require "test_helper"
require "rack/test"
require_relative "../support/synthetic_pdf_helper"

class AdminBasWorkflowUiTest < ActionDispatch::IntegrationTest
  include SyntheticPdfHelper

  setup do
    login_as_admin
  end

  test "BAS job page shows guided workflow labels warnings and document next actions" do
    job = create_job(reporting_method: "unknown", gst_basis: "unknown")
    csv_document(job, "Synthetic CSV Bank Statement", "bank_statement")
    pdf_document(job)
    csv_document(job, "Synthetic Receipt", "receipt")

    get admin_bas_job_path(job)

    assert_response :success
    assert_select "h1", "Synthetic Workflow UI Client Pty Ltd"
    assert_select ".bas-workspace-heading .admin-actions a", "Upload source file"
    assert_select ".bas-workspace-heading .admin-actions a", "Import uploaded files"
    assert_select ".bas-workspace-heading .admin-actions a", "Back to BAS"
    assert_select ".bas-workspace-heading .admin-actions a", text: "Review matching", count: 0
    assert_select ".bas-workspace-heading .admin-actions a", text: "Calculate BAS report", count: 0
    assert_select "nav.bas-workspace-tabs"
    assert_select "a", "Overview"
    assert_select "a", "Files & imports"
    assert_select "a", "Matches & queries"
    assert_select "a", "Reports"
    assert_select "a", text: "AI review", count: 0
    assert_includes response.body, %(href="#{admin_bas_job_path(job, tab: 'documents')}")
    assert_includes response.body, %(href="#{admin_bas_job_path(job, tab: 'matching')}")
    assert_includes response.body, %(href="#{admin_bas_job_path(job, tab: 'report')}")
    assert_select ".bas-workspace-tabs a[aria-current='page']", "Overview"
    assert_empty top_action_labels(response.body) & workspace_tab_labels(response.body)
    assert_select "#overview" do
      assert_select "h2", "Overview"
      assert_select ".bas-next-step-card", text: /Next step: Import uploaded files/
    end
    assert_select "#documents-imports", count: 0
    assert_select "#matching-queries", count: 0
    assert_select "#report-snapshots", count: 0
    assert_select "#audit-admin", count: 0
    assert_select "td", text: "Synthetic CSV Bank Statement", count: 0
    assert_select "h2", text: "Uploaded source/supporting files", count: 0
    assert_select "h2", text: "Open client/internal queries", count: 0
    assert_select "h2", text: "Recent report snapshots", count: 0
    assert_select "h2", text: "Danger zone", count: 0
    assert_select "h2", "BAS workflow"
    assert_select "h3", "Step 1: Upload files"
    assert_select "h3", "Step 2: Import / convert"
    assert_select "h3", "Step 3: Match records"
    assert_select "h3", "Step 4: Generate client queries"
    assert_select "h3", "Step 5: Review BAS report"
    assert_select "h3", "Step 6: Snapshot / approve / lock"

    assert_includes response.body, "Upload source file"
    assert_includes response.body, "Import uploaded files"
    assert_includes response.body, "Review matching"
    assert_includes response.body, "Calculate BAS report"

    assert_select ".bas-warning-banner", text: /Reporting method is unknown/

    get admin_bas_job_path(job, tab: "documents")

    assert_response :success
    assert_select "#overview", count: 0
    assert_select "#documents-imports" do
      assert_select "h2", "Files & imports"
      assert_select "h2", "Uploaded source/supporting files"
      assert_select "td", "Synthetic CSV Bank Statement"
      assert_select "a", "PDF bank statement history"
      assert_select "td", text: /Stored only - no import needed/
      assert_select "button", "Convert PDF to preview"
      assert_select "a", "Start CSV/XLSX import"
    end
    assert_select "#matching-queries", count: 0
    assert_select "#audit-admin", count: 0

    get admin_bas_job_path(job, tab: "audit")

    assert_response :success
    assert_select "#audit-admin" do
      assert_select "h2", "Recent audit events"
      assert_select "h2", "Danger zone"
    end
    assert_select "#overview", count: 0
    assert_select "#documents-imports", count: 0
  end

  test "job page explains no open query state and disables email draft action" do
    job = create_job

    get admin_bas_job_path(job, tab: "matching")

    assert_response :success
    assert_select "#matching-queries" do
      assert_select "h2", "Matches & queries"
      assert_select "h2", "Generate client queries"
      assert_select "h2", "Open client/internal queries"
    end
    assert_includes response.body, "No open queries. Generate client queries after matching review if unresolved items remain."
    assert_includes response.body, "Available after open queries are generated."
    assert_select "a[href='#{admin_bas_job_query_email_draft_path(job)}']", count: 0
  end

  test "job page open queries table shows source details and review action" do
    job = create_job
    transaction = BasBankTransaction.create!(
      bas_job: job,
      transaction_date: Date.new(2026, 3, 12),
      description: "Generic supplier card purchase",
      amount: BigDecimal("77.00"),
      status: "imported"
    )
    query = BasQuery.create!(
      bas_job: job,
      title: "Unmatched bank transaction",
      query_type: "unmatched_bank_transaction",
      status: "open",
      source_type: "BasBankTransaction",
      source_id: transaction.id,
      auto_generated: true
    )

    get admin_bas_job_path(job, tab: "matching")

    assert_response :success
    assert_select "th", "Query"
    assert_select "th", "Source"
    assert_includes response.body, "Generic supplier card purchase"
    assert_includes response.body, "$77.00"
    assert_select "a[href='#{edit_admin_bas_job_query_path(job, query)}']", text: "Review query"
    assert_select "a[href='#{admin_bas_job_query_email_draft_path(job)}']", text: "Generate client email draft"
  end

  test "workspace tabs highlight the selected query-param tab" do
    job = create_job

    {
      nil => "Overview",
      "documents" => "Files & imports",
      "matching" => "Matches & queries",
      "report" => "Reports",
      "audit" => "Audit & admin"
    }.each do |tab, label|
      path = tab.present? ? admin_bas_job_path(job, tab: tab) : admin_bas_job_path(job)
      get path

      assert_response :success
      assert_select ".bas-workspace-tabs a[aria-current='page']", label
      assert_equal [ label ], workspace_active_tab_labels(response.body)
    end
  end

  test "workspace tabs have sticky safe styling hooks" do
    job = create_job

    get admin_bas_job_path(job)

    assert_response :success
    assert_select "nav.bas-workspace-tabs"
    assert_select ".bas-workspace-section#overview"

    css = Rails.root.join("app/assets/tailwind/application.css").read
    assert_match(/\.bas-workspace-tabs\s*\{[^}]*position: sticky/m, css)
    assert_match(/\.bas-workspace-tabs\s*\{[^}]*z-index: 30/m, css)
    assert_match(/\.bas-workspace-tabs\s*\{[^}]*background: #ffffff/m, css)
    assert_match(/\.bas-workspace-section\s*\{[^}]*scroll-margin-top/m, css)
  end

  test "query review page shows source context" do
    job = create_job
    invoice = BasInvoice.create!(
      bas_job: job,
      invoice_number: "INV-CTX",
      issue_date: Date.new(2026, 3, 15),
      party_name: "Generic supplier",
      total_amount: BigDecimal("132.00"),
      gst_amount: BigDecimal("12.00"),
      status: "imported"
    )
    query = BasQuery.create!(
      bas_job: job,
      title: "Unmatched invoice",
      query_type: "unmatched_invoice",
      source_type: "BasInvoice",
      source_id: invoice.id,
      auto_generated: true
    )

    get edit_admin_bas_job_query_path(job, query)

    assert_response :success
    assert_select "h1", "Review query"
    assert_guarded_form admin_bas_job_query_path(job, query), "Saving query"
    assert_select "button[data-submit-guard-loading-text='Saving query']", text: "Save query"
    assert_select "h2", "Source context"
    assert_includes response.body, "Source type"
    assert_includes response.body, "Invoice"
    assert_includes response.body, "2026-03-15"
    assert_includes response.body, "Generic supplier"
    assert_includes response.body, "$132.00"
    assert_includes response.body, "INV-CTX"
    assert_includes response.body, "Imported"
  end

  test "key BAS mutation forms render submit guard loading attributes" do
    job = create_job(gst_basis: "cash", reporting_method: "simpler_bas")
    document = csv_document(job, "Synthetic CSV Bank Statement", "bank_statement")
    import_run = BasImportRun.create!(
      bas_job: job,
      bas_document: document,
      import_type: "bank_statement",
      status: "previewed",
      row_count: 1,
      preview_rows: [
        {
          "row_number" => 1,
          "data" => {
            "Date" => "01/01/2026",
            "Description" => "Synthetic item",
            "Amount" => "1.00"
          }
        }
      ]
    )
    BasBankTransaction.create!(
      bas_job: job,
      bas_import_run: import_run,
      transaction_date: Date.new(2026, 1, 2),
      description: "Synthetic ready record",
      amount: BigDecimal("110.00"),
      status: "ignored"
    )

    with_modified_env("BAS_AI_UI_ENABLED" => "true", "BAS_AI_ENABLED" => "true", "BAS_AI_PROVIDER" => "stub", "BAS_AI_MODEL" => "synthetic-model") do
      get admin_bas_job_ai_runs_path(job)
    end
    assert_response :success
    assert_guarded_form admin_bas_job_ai_runs_path(job), "Running AI"
    assert_select "button[data-submit-guard-loading-text='Running AI']", text: "Run AI"

    get admin_bas_job_matching_path(job)
    assert_response :success
    assert_guarded_form run_admin_bas_job_matching_path(job), "Creating suggestions"
    assert_guarded_form generate_queries_admin_bas_job_matching_path(job), "Generating queries"

    get admin_bas_job_import_run_path(job, import_run)
    assert_response :success
    assert_guarded_form confirm_admin_bas_job_import_run_path(job, import_run), "Importing"

    get admin_bas_job_report_path(job)
    assert_response :success
    assert_guarded_form calculate_admin_bas_job_report_path(job), "Calculating"

    get admin_bas_job_report_snapshots_path(job)
    assert_response :success
    assert_guarded_form admin_bas_job_report_snapshots_path(job), "Generating draft"

    get admin_bas_job_path(job, tab: "audit")
    assert_response :success
    assert_guarded_form admin_bas_job_path(job), "Deleting"
    assert_select "form[action='#{admin_bas_job_path(job)}'][data-turbo-confirm]"
  end

  test "submit guard controller is wired for visible Turbo loading and validation reset" do
    helper_source = Rails.root.join("app/helpers/admin/bas/workflow_helper.rb").read
    controller_source = Rails.root.join("app/javascript/controllers/submit_guard_controller.js").read
    css_source = Rails.root.join("app/assets/tailwind/application.css").read

    assert_includes helper_source, "click->submit-guard#rememberSubmitter"
    assert_includes helper_source, "turbo:submit-start->submit-guard#submitStart"
    assert_includes helper_source, "turbo:submit-end->submit-guard#submitEnd"
    assert_includes controller_source, "button.replaceChildren(this.spinnerElement(), document.createTextNode(loadingText))"
    assert_includes controller_source, "if (event.detail && event.detail.success) return"
    assert_includes css_source, ".submit-guard-spinner"
    assert_includes css_source, "form.is-submitting"
  end

  private

  def login_as_admin
    with_modified_env("ADMIN_USERNAME" => "bas-workflow-ui-admin", "ADMIN_PASSWORD" => "secret-password") do
      post admin_login_path, params: { username: "bas-workflow-ui-admin", password: "secret-password" }
      assert_redirected_to admin_root_path
    end
  end

  def create_client
    BasClient.create!(
      legal_name: "Synthetic Workflow UI Client Pty Ltd",
      default_gst_basis: "unknown",
      default_reporting_method: "unknown"
    )
  end

  def create_job(attributes = {})
    BasJob.create!({
      bas_client: create_client,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      payroll_applicable: true,
      cash_transactions_applicable: true
    }.merge(attributes))
  end

  def csv_document(job, title, document_type)
    document = job.documents.build(
      title: title,
      document_type: document_type,
      uploaded_by: "bas-workflow-ui-admin"
    )
    document.file.attach(csv_upload)
    document.save!
    document
  end

  def pdf_document(job)
    document = job.documents.build(
      title: "Synthetic PDF Bank Statement",
      document_type: "bank_statement",
      uploaded_by: "bas-workflow-ui-admin"
    )
    attach_synthetic_pdf(document, text: sample_statement_text)
    document.save!
    document
  end

  def csv_upload
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/bas_bank_statement.csv").to_s,
      "text/csv"
    )
  end

  def sample_statement_text
    <<~TEXT
      Date Description Debit Credit Balance
      01/01/2026 Synthetic debit 12.34 987.66
    TEXT
  end

  def top_action_labels(body)
    Nokogiri::HTML(body).css(".bas-workspace-heading .admin-actions a").map { |node| node.text.squish }
  end

  def workspace_tab_labels(body)
    Nokogiri::HTML(body).css(".bas-workspace-tabs a").map { |node| node.text.squish }
  end

  def workspace_active_tab_labels(body)
    Nokogiri::HTML(body).css(".bas-workspace-tabs a[aria-current='page']").map { |node| node.text.squish }
  end

  def assert_guarded_form(action, loading_text)
    form = Nokogiri::HTML(response.body).at_css("form[action='#{action}'][data-controller='submit-guard'][data-submit-guard-loading-text-value='#{loading_text}']")

    assert form, "Expected guarded form #{action} with loading text #{loading_text.inspect}"
    assert_includes form["data-action"], "click->submit-guard#rememberSubmitter"
    assert_includes form["data-action"], "submit->submit-guard#submit"
    assert_includes form["data-action"], "turbo:submit-start->submit-guard#submitStart"
    assert_includes form["data-action"], "turbo:submit-end->submit-guard#submitEnd"
  end
end
