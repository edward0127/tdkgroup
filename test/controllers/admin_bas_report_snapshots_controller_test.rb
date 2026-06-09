require "test_helper"

class AdminBasReportSnapshotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    login_as_admin
  end

  test "report snapshot page shows breakdown links" do
    job = bas_job
    invoice(job, direction: "sale")
    snapshot = snapshot_for(job)

    get admin_bas_job_report_snapshot_path(job, snapshot)

    assert_response :success
    assert_select "a[href='#{breakdown_admin_bas_job_report_snapshot_path(job, snapshot, "g1")}']", "View breakdown"
    assert_select "a[href='#{breakdown_admin_bas_job_report_snapshot_path(job, snapshot, "1a")}']", "View breakdown"
    assert_select "a[href='#{breakdown_admin_bas_job_report_snapshot_path(job, snapshot, "1b")}']", "View breakdown"
    assert_select "a[href='#{breakdown_admin_bas_job_report_snapshot_path(job, snapshot, "net_gst")}']", "View formula"
  end

  test "G1 breakdown includes sales invoice and cash sales records" do
    job = bas_job
    invoice(job, direction: "sale", invoice_number: "INV-G1", party_name: "G1 Customer")
    cash_transaction(job, direction: "cash_receipt", party_name: "Cash Sale Customer", description: "Cash sale")
    snapshot = snapshot_for(job)

    get breakdown_admin_bas_job_report_snapshot_path(job, snapshot, "g1")

    assert_response :success
    included = section_text("included-records")
    assert_includes included, "INV-G1"
    assert_includes included, "Cash Sale Customer"
    assert_includes response.body, "Accrual basis: figures are based on invoice issue/accrual records where applicable."
  end

  test "1A breakdown includes GST on sales records" do
    job = bas_job
    invoice(job, direction: "sale", invoice_number: "INV-1A", party_name: "GST Sales Customer", gst_amount: "10.00")
    snapshot = snapshot_for(job)

    get breakdown_admin_bas_job_report_snapshot_path(job, snapshot, "1a")

    assert_response :success
    included = section_text("included-records")
    assert_includes included, "INV-1A"
    assert_includes included, "$10.00"
    assert_includes included, "Taxable sale GST included in 1A"
  end

  test "1B breakdown includes GST purchase records" do
    job = bas_job
    invoice(job, direction: "purchase", invoice_number: "BILL-1B", party_name: "GST Supplier", total_amount: "55.00", gst_amount: "5.00")
    snapshot = snapshot_for(job)

    get breakdown_admin_bas_job_report_snapshot_path(job, snapshot, "1b")

    assert_response :success
    included = section_text("included-records")
    assert_includes included, "BILL-1B"
    assert_includes included, "GST Supplier"
    assert_includes included, "Taxable purchase GST credit included in 1B"
  end

  test "net GST breakdown shows formula" do
    job = bas_job
    invoice(job, direction: "sale", total_amount: "110.00", gst_amount: "10.00")
    invoice(job, direction: "purchase", total_amount: "55.00", gst_amount: "5.00")
    snapshot = snapshot_for(job)

    get breakdown_admin_bas_job_report_snapshot_path(job, snapshot, "net_gst")

    assert_response :success
    formula = section_text("net-gst-formula")
    assert_includes formula, "Net GST = 1A GST on sales - 1B GST on purchases"
    assert_includes formula, "$10.00"
    assert_includes formula, "$5.00"
  end

  test "ignored and excluded records do not appear as included records" do
    job = bas_job
    invoice(job, direction: "sale", invoice_number: "INV-INCLUDED", party_name: "Included Customer")
    invoice(job, direction: "sale", invoice_number: "INV-IGNORED", party_name: "Ignored Customer", status: "ignored")
    invoice(job, direction: "sale", invoice_number: "INV-EXCLUDED", party_name: "Excluded Customer", gst_code: "bas_excluded")
    snapshot = snapshot_for(job)

    get breakdown_admin_bas_job_report_snapshot_path(job, snapshot, "g1")

    assert_response :success
    included = section_text("included-records")
    excluded = section_text("excluded-records")
    assert_includes included, "INV-INCLUDED"
    assert_not_includes included, "INV-IGNORED"
    assert_not_includes included, "INV-EXCLUDED"
    assert_includes excluded, "INV-IGNORED"
    assert_includes excluded, "INV-EXCLUDED"
  end

  test "manual adjustments appear clearly" do
    job = bas_job
    adjustment(job, adjustment_type: "total_sales", label: "G1 review adjustment", amount: "12.00")
    snapshot = snapshot_for(job)

    get breakdown_admin_bas_job_report_snapshot_path(job, snapshot, "g1")

    assert_response :success
    manual_adjustments = section_text("manual-adjustments")
    assert_includes manual_adjustments, "G1 review adjustment"
    assert_includes manual_adjustments, "Manual adjustment included in G1 total sales"
  end

  test "cash and accrual basis breakdowns use existing calculator basis details" do
    cash_job = bas_job(gst_basis: "cash")
    cash_invoice = invoice(cash_job, direction: "sale", invoice_number: "INV-CASH", issue_date: Date.new(2025, 12, 20), status: "matched")
    bank_record = bank_transaction(cash_job, transaction_date: Date.new(2026, 1, 10), status: "matched")
    accepted_match(cash_job, cash_invoice, bank_record)
    cash_snapshot = snapshot_for(cash_job)

    get breakdown_admin_bas_job_report_snapshot_path(cash_job, cash_snapshot, "g1")

    assert_response :success
    assert_includes response.body, "Cash basis: figures are based on paid/matched transactions where applicable."
    assert_includes section_text("included-records"), "INV-CASH"

    accrual_job = bas_job(gst_basis: "accrual")
    invoice(accrual_job, direction: "sale", invoice_number: "INV-ACCRUAL", issue_date: Date.new(2026, 1, 15))
    accrual_snapshot = snapshot_for(accrual_job)

    get breakdown_admin_bas_job_report_snapshot_path(accrual_job, accrual_snapshot, "g1")

    assert_response :success
    assert_includes response.body, "Accrual basis: figures are based on invoice issue/accrual records where applicable."
    assert_includes section_text("included-records"), "INV-ACCRUAL"
  end

  test "breakdown links to source records matches and queries where routes exist" do
    job = bas_job(gst_basis: "cash")
    invoice_record = invoice(job, direction: "sale", invoice_number: "INV-LINK", status: "matched")
    bank_record = bank_transaction(job, reference: "BANK-LINK", status: "matched")
    match = accepted_match(job, invoice_record, bank_record)
    query = BasQuery.create!(
      bas_job: job,
      source_type: "BasInvoice",
      source_id: invoice_record.id,
      title: "Confirm linked invoice"
    )
    snapshot = snapshot_for(job)

    get breakdown_admin_bas_job_report_snapshot_path(job, snapshot, "g1")

    assert_response :success
    assert_select "a[href='#{admin_bas_job_invoice_path(job, invoice_record)}']", "INV-LINK"
    assert_select "a[href='#{admin_bas_job_bank_transaction_path(job, bank_record)}']", "BANK-LINK"
    assert_select "a[href='#{admin_bas_job_match_path(job, match)}']", "Match ##{match.id}"
    assert_select "a[href='#{admin_bas_job_query_path(job, query)}']", "Query ##{query.id}"
  end

  test "breakdown CSV downloads by BAS label" do
    job = bas_job
    invoice(job, direction: "sale", invoice_number: "INV-CSV")
    snapshot = snapshot_for(job)

    get download_breakdown_csv_admin_bas_job_report_snapshot_path(job, snapshot, label: "g1")

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.body, "G1 total sales"
    assert_includes response.body, "INV-CSV"
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
      bas_client: BasClient.create!(legal_name: "Synthetic Snapshot Client Pty Ltd"),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      gst_basis: "accrual",
      reporting_method: "simpler_bas",
      payroll_applicable: false
    }.merge(attributes))
  end

  def snapshot_for(job)
    BasReports::SnapshotBuilder.new(bas_job: job, actor_username: "phase4-admin").create_draft!
  end

  def invoice(job, attributes = {})
    BasInvoice.create!({
      bas_job: job,
      direction: "sale",
      invoice_number: "INV-#{SecureRandom.hex(2)}",
      issue_date: Date.new(2026, 1, 15),
      party_name: "Synthetic Customer",
      total_amount: BigDecimal("110.00"),
      gst_amount: BigDecimal("10.00"),
      payment_method: "bank",
      gst_code: "taxable",
      status: "imported"
    }.merge(attributes))
  end

  def bank_transaction(job, attributes = {})
    BasBankTransaction.create!({
      bas_job: job,
      transaction_date: Date.new(2026, 1, 20),
      description: "Synthetic payment",
      reference: "BANK-#{SecureRandom.hex(2)}",
      amount: BigDecimal("110.00"),
      status: "imported"
    }.merge(attributes))
  end

  def cash_transaction(job, attributes = {})
    BasCashTransaction.create!({
      bas_job: job,
      transaction_date: Date.new(2026, 1, 20),
      party_name: "Synthetic Cash Customer",
      description: "Synthetic cash transaction",
      direction: "cash_receipt",
      total_amount: BigDecimal("55.00"),
      gst_amount: BigDecimal("5.00"),
      gst_code: "taxable",
      status: "imported"
    }.merge(attributes))
  end

  def adjustment(job, attributes = {})
    BasAdjustment.create!({
      bas_job: job,
      adjustment_type: "gst_on_sales",
      label: "Synthetic adjustment",
      amount: BigDecimal("1.00"),
      reason: "Synthetic review reason",
      created_by: "phase4-admin"
    }.merge(attributes))
  end

  def accepted_match(job, invoice_record, payment_record, attributes = {})
    match = BasMatch.create!({
      bas_job: job,
      match_type: payment_record.is_a?(BasCashTransaction) ? "invoice_to_cash_transaction" : "invoice_to_bank_transaction",
      status: "accepted",
      matched_amount: invoice_record.total_amount,
      accepted_at: Time.current,
      accepted_by: "phase4-admin"
    }.merge(attributes))
    match.items.create!(matchable: invoice_record, amount: invoice_record.total_amount)
    amount = payment_record.respond_to?(:amount) ? payment_record.amount : payment_record.total_amount
    match.items.create!(matchable: payment_record, amount: amount)
    match
  end

  def section_text(id)
    Nokogiri::HTML(response.body).at_css("##{id}").text.squish
  end
end
