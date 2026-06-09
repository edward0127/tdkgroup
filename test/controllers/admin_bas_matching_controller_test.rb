require "test_helper"

class AdminBasMatchingControllerTest < ActionDispatch::IntegrationTest
  setup do
    login_as_admin
  end

  test "non-admin cannot access matching pages or actions" do
    job = create_job_with_bank_match_candidate

    reset!

    get admin_bas_job_matching_path(job)
    assert_redirected_to admin_login_path

    post run_admin_bas_job_matching_path(job)
    assert_redirected_to admin_login_path
  end

  test "admin can view matching page and run matching" do
    job = create_job_with_bank_match_candidate

    get admin_bas_job_matching_path(job)
    assert_response :success
    assert_select "h1", "Matching & review"
    assert_includes response.body, "Client: #{job.bas_client.primary_name}"

    assert_difference "BasMatch.count", 1 do
      assert_difference "BasAuditEvent.count", 2 do
        post run_admin_bas_job_matching_path(job)
      end
    end

    assert_redirected_to admin_bas_job_matching_path(job)
    assert_equal "bas-matching-admin", BasAuditEvent.last.actor_username
    assert_equal "bas_matching_run", BasAuditEvent.last.event_type
  end

  test "matching mutation forms include visible submit guard loading text" do
    job = create_job_with_bank_match_candidate

    get admin_bas_job_matching_path(job)

    assert_response :success
    assert_guarded_form run_admin_bas_job_matching_path(job), "Creating suggestions"
    assert_guarded_form generate_queries_admin_bas_job_matching_path(job), "Generating queries"

    BasMatching::Matcher.new(bas_job: job, actor_username: "bas-matching-admin").call
    match = BasMatch.last

    get admin_bas_job_matches_path(job)

    assert_response :success
    assert_guarded_form accept_admin_bas_job_match_path(job, match), "Accepting"
    assert_guarded_form reject_admin_bas_job_match_path(job, match), "Rejecting"
    assert_guarded_form mark_needs_review_admin_bas_job_match_path(job, match), "Marking review"
  end

  test "admin can accept and reject proposed matches" do
    job = create_job_with_bank_match_candidate
    BasMatching::Matcher.new(bas_job: job, actor_username: "bas-matching-admin").call
    accepted_match = BasMatch.last

    post accept_admin_bas_job_match_path(job, accepted_match)

    assert_redirected_to admin_bas_job_matching_path(job)
    assert_equal "accepted", accepted_match.reload.status
    assert_equal "bas-matching-admin", accepted_match.accepted_by
    assert accepted_match.items.all? { |item| item.matchable.reload.status == "matched" }
    assert_equal "bas_match_accepted", BasAuditEvent.last.event_type

    rejected_job = create_job_with_bank_match_candidate
    BasMatching::Matcher.new(bas_job: rejected_job, actor_username: "bas-matching-admin").call
    rejected_match = BasMatch.last

    post reject_admin_bas_job_match_path(rejected_job, rejected_match)

    assert_redirected_to admin_bas_job_matching_path(rejected_job)
    assert_equal "rejected", rejected_match.reload.status
    assert_equal "bas-matching-admin", rejected_match.rejected_by
    assert_equal "bas_match_rejected", BasAuditEvent.last.event_type
  end

  test "admin can create manual match" do
    job = create_job_with_bank_match_candidate
    invoice = job.invoices.first
    bank_transaction = job.bank_transactions.first

    assert_difference "BasMatch.count", 1 do
      post admin_bas_job_matches_path(job), params: {
        bas_match: {
          invoice_ids: [ invoice.id ],
          bank_transaction_id: bank_transaction.id,
          matched_amount: "110.00",
          notes: "Synthetic manual match"
        }
      }
    end

    match = BasMatch.last
    assert_redirected_to admin_bas_job_match_path(job, match)
    assert_equal "manual", match.match_type
    assert_equal "accepted", match.status
    assert_equal "matched", invoice.reload.status
    assert_equal "matched", bank_transaction.reload.status
    assert_equal "bas_manual_match_created", BasAuditEvent.last.event_type
  end

  test "admin can mark imported records ignored or needs review" do
    job = create_job_with_bank_match_candidate
    bank_transaction = job.bank_transactions.first
    invoice = job.invoices.first
    cash_transaction = cash_transaction_for(job)

    post ignore_admin_bas_job_bank_transaction_path(job, bank_transaction), params: { notes: "Synthetic ignore note" }
    assert_redirected_to admin_bas_job_bank_transactions_path(job)
    assert_equal "ignored", bank_transaction.reload.status
    assert_equal "bas_item_ignored", BasAuditEvent.last.event_type

    post ignore_admin_bas_job_invoice_path(job, invoice)
    assert_redirected_to admin_bas_job_invoices_path(job)
    assert_equal "ignored", invoice.reload.status

    post mark_needs_review_admin_bas_job_cash_transaction_path(job, cash_transaction)
    assert_redirected_to admin_bas_job_cash_transactions_path(job)
    assert_equal "needs_review", cash_transaction.reload.status
    assert_equal "bas_item_needs_review", BasAuditEvent.last.event_type
  end

  test "ignore actions auto resolve related generated source queries" do
    job = create_job_with_bank_match_candidate
    bank_transaction = job.bank_transactions.first
    invoice = job.invoices.first
    bank_query = generated_query_for(job, bank_transaction, query_type: "unmatched_bank_transaction")
    invoice_query = generated_query_for(job, invoice, query_type: "unmatched_invoice")

    assert_difference -> { BasAuditEvent.where(event_type: "bas_query_auto_resolved").count }, 1 do
      post ignore_admin_bas_job_bank_transaction_path(job, bank_transaction)
    end
    assert_equal "resolved", bank_query.reload.status
    assert_equal BasQueries::SourceResolutionSync::RESOLUTION_NOTE, bank_query.resolution_notes

    assert_difference -> { BasAuditEvent.where(event_type: "bas_query_auto_resolved").count }, 1 do
      post ignore_admin_bas_job_invoice_path(job, invoice)
    end
    assert_equal "resolved", invoice_query.reload.status
  end

  test "admin can generate queries" do
    job = create_job_with_bank_match_candidate

    assert_difference "BasQuery.count", 2 do
      post generate_queries_admin_bas_job_matching_path(job)
    end

    assert_redirected_to admin_bas_job_matching_path(job, anchor: "open-client-queries")
    assert_equal "bas_queries_generated", BasAuditEvent.last.event_type
    assert_equal "bas-matching-admin", BasAuditEvent.last.actor_username
    assert_equal "2 client queries generated.", flash[:notice]
    follow_redirect!
    assert_response :success
    assert_select "h2", "Open client queries"
    assert_select "a[href='#{admin_bas_job_path(job, tab: 'matching', anchor: 'open-queries')}']", text: "View open queries"

    assert_no_difference "BasQuery.count" do
      post generate_queries_admin_bas_job_matching_path(job)
    end
    assert_equal "No new client queries needed. 2 existing queries already covered these unresolved items.", flash[:notice]
  end

  test "generate client queries is blocked when proposed matches exist" do
    job = create_job_with_bank_match_candidate
    BasMatching::Matcher.new(bas_job: job, actor_username: "bas-matching-admin").call

    get admin_bas_job_matching_path(job)
    assert_response :success
    assert_select "button[disabled]", text: "Generate client queries"
    assert_includes response.body, "Review 1 proposed/needs-review matches before generating client queries."

    assert_no_difference "BasQuery.count" do
      post generate_queries_admin_bas_job_matching_path(job)
    end

    assert_redirected_to admin_bas_job_matching_path(job)
    assert_equal "Review 1 proposed/needs-review matches before generating client queries.", flash[:alert]
  end

  test "generate client queries is enabled after proposed matches are resolved" do
    job = create_job_with_bank_match_candidate
    BasMatching::Matcher.new(bas_job: job, actor_username: "bas-matching-admin").call
    BasMatch.last.update!(status: "rejected", rejected_at: Time.current, rejected_by: "bas-matching-admin")

    get admin_bas_job_matching_path(job)

    assert_response :success
    assert_select "button[disabled]", text: "Generate client queries", count: 0
    assert_select "form[action='#{generate_queries_admin_bas_job_matching_path(job)}'] button", text: "Generate client queries"
  end

  test "accept from workflow returns to matching page with remaining count" do
    job = create_job_with_bank_match_candidate
    BasMatching::Matcher.new(bas_job: job, actor_username: "bas-matching-admin").call
    match = BasMatch.last

    post accept_admin_bas_job_match_path(job, match), params: { return_to: "workflow" }

    assert_redirected_to admin_bas_job_matching_path(job)
    assert_equal "Match accepted. No proposed/needs-review matches remaining.", flash[:notice]
  end

  test "accepting match auto resolves related generated source queries" do
    job = create_job_with_bank_match_candidate
    BasMatching::Matcher.new(bas_job: job, actor_username: "bas-matching-admin").call
    match = BasMatch.last
    invoice = job.invoices.first
    bank_transaction = job.bank_transactions.first
    invoice_query = generated_query_for(job, invoice, query_type: "unmatched_invoice")
    bank_query = generated_query_for(job, bank_transaction, query_type: "unmatched_bank_transaction")

    assert_difference -> { BasAuditEvent.where(event_type: "bas_query_auto_resolved").count }, 2 do
      post accept_admin_bas_job_match_path(job, match), params: { return_to: "workflow" }
    end

    assert_equal "resolved", invoice_query.reload.status
    assert_equal "resolved", bank_query.reload.status
  end

  test "matches list identifies return to matching workflow" do
    job = create_job_with_bank_match_candidate
    BasMatching::Matcher.new(bas_job: job, actor_username: "bas-matching-admin").call

    get admin_bas_job_matches_path(job)

    assert_response :success
    assert_select "h1", "BAS matches"
    assert_select "a[href='#{admin_bas_job_matching_path(job)}']", text: "Back to matching workflow"
    assert_includes response.body, "This page lists created matches. Use the matching workflow page to create suggestions and generate client queries."
  end

  test "generate client queries is blocked when needs review matches exist" do
    job = create_job_with_bank_match_candidate
    match = BasMatch.create!(
      bas_job: job,
      match_type: "manual",
      status: "needs_review",
      matched_amount: BigDecimal("110.00"),
      created_by_rule: "manual"
    )

    assert_no_difference "BasQuery.count" do
      post generate_queries_admin_bas_job_matching_path(job)
    end

    assert_redirected_to admin_bas_job_matching_path(job)
    assert_equal "needs_review", match.reload.status
    assert_equal "Review 1 proposed/needs-review matches before generating client queries.", flash[:alert]
  end

  test "generate client queries works once proposed matches are rejected" do
    job = create_job_with_bank_match_candidate
    BasMatching::Matcher.new(bas_job: job, actor_username: "bas-matching-admin").call
    match = BasMatch.last
    match.update!(status: "rejected", rejected_at: Time.current, rejected_by: "bas-matching-admin")

    assert_difference "BasQuery.count", 2 do
      post generate_queries_admin_bas_job_matching_path(job)
    end

    assert_redirected_to admin_bas_job_matching_path(job, anchor: "open-client-queries")
    assert_equal "bas_queries_generated", BasAuditEvent.last.event_type
  end

  test "locked job blocks matching actions" do
    job = create_job_with_bank_match_candidate(status: "locked")
    bank_transaction = job.bank_transactions.first

    assert_no_difference "BasMatch.count" do
      post run_admin_bas_job_matching_path(job)
    end
    assert_redirected_to admin_bas_job_matching_path(job)

    assert_no_difference "BasQuery.count" do
      post generate_queries_admin_bas_job_matching_path(job)
    end
    assert_redirected_to admin_bas_job_matching_path(job)

    assert_no_changes -> { bank_transaction.reload.status } do
      post ignore_admin_bas_job_bank_transaction_path(job, bank_transaction)
    end
    assert_redirected_to admin_bas_job_bank_transactions_path(job)
  end

  private

  def login_as_admin
    with_modified_env("ADMIN_USERNAME" => "bas-matching-admin", "ADMIN_PASSWORD" => "secret-password") do
      post admin_login_path, params: { username: "bas-matching-admin", password: "secret-password" }
      assert_redirected_to admin_root_path
    end
  end

  def create_job_with_bank_match_candidate(attributes = {})
    job = BasJob.create!({
      bas_client: BasClient.create!(legal_name: "Synthetic Matching Client Pty Ltd"),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31)
    }.merge(attributes))
    invoice_for(job)
    bank_transaction_for(job)
    job
  end

  def invoice_for(job)
    BasInvoice.create!(
      bas_job: job,
      direction: "sale",
      invoice_number: "INV-001",
      issue_date: Date.new(2026, 1, 1),
      paid_date: Date.new(2026, 1, 2),
      party_name: "Synthetic Customer",
      total_amount: BigDecimal("110.00"),
      gst_amount: BigDecimal("10.00"),
      payment_method: "bank",
      gst_code: "taxable",
      status: "imported"
    )
  end

  def bank_transaction_for(job)
    BasBankTransaction.create!(
      bas_job: job,
      transaction_date: Date.new(2026, 1, 2),
      description: "Synthetic Customer payment",
      amount: BigDecimal("110.00"),
      status: "imported"
    )
  end

  def cash_transaction_for(job)
    BasCashTransaction.create!(
      bas_job: job,
      transaction_date: Date.new(2026, 1, 3),
      party_name: "Synthetic Cash Customer",
      description: "Synthetic cash item",
      total_amount: BigDecimal("22.00"),
      gst_code: "taxable",
      status: "imported"
    )
  end

  def generated_query_for(job, source, attributes = {})
    job.queries.create!({
      title: "Generated source query",
      query_type: "other",
      status: "open",
      source_type: source.class.name,
      source_id: source.id,
      dedupe_key: "controller-sync:#{SecureRandom.hex(8)}",
      generated_by_rule: "controller_sync",
      auto_generated: true,
      created_by: "bas-matching-admin",
      updated_by: "bas-matching-admin"
    }.merge(attributes))
  end

  def assert_guarded_form(action, loading_text)
    form = Nokogiri::HTML(response.body).at_css("form[action='#{action}'][data-controller='submit-guard'][data-submit-guard-loading-text-value='#{loading_text}']")

    assert form, "Expected guarded form #{action} with loading text #{loading_text.inspect}"
    assert_includes form["data-action"], "click->submit-guard#rememberSubmitter"
    assert_includes form["data-action"], "turbo:submit-start->submit-guard#submitStart"
  end
end
