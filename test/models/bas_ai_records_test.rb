require "test_helper"

class BasAiRecordsTest < ActiveSupport::TestCase
  test "job review ai extraction run ignores selected documents" do
    job = bas_job
    other_job = bas_job(legal_name: "Other Synthetic AI Client Pty Ltd")
    run = BasAiExtractionRun.new(
      bas_job: job,
      bas_document: bas_document(other_job),
      status: "completed",
      input_kind: "job_review",
      metadata: { safe_id: 1 }
    )

    assert run.valid?
    assert_nil run.bas_document
  end

  test "document ai extraction run validates allowlists document ownership and safe metadata" do
    job = bas_job
    other_job = bas_job(legal_name: "Other Synthetic AI Client Pty Ltd")
    run = BasAiExtractionRun.new(
      bas_job: job,
      bas_document: bas_document(other_job),
      status: "completed",
      input_kind: "document_text",
      metadata: { safe_id: 1 }
    )

    assert_not run.valid?
    assert_includes run.errors[:bas_document], "must belong to the same BAS job"

    run.bas_document = bas_document(job)
    run.status = "posted"
    run.input_kind = "everything"
    run.metadata = { raw_prompt: "do not store this" }

    assert_not run.valid?
    assert_equal :inclusion, run.errors.details[:status].first.fetch(:error)
    assert_equal :inclusion, run.errors.details[:input_kind].first.fetch(:error)
    assert_includes run.errors[:metadata], "must not contain raw prompt, document text, responses or secrets"
  end

  test "ai suggestion validates allowlists confidence and run ownership" do
    job = bas_job
    other_job = bas_job(legal_name: "Other Synthetic AI Client Pty Ltd")
    suggestion = BasAiSuggestion.new(
      bas_job: job,
      bas_ai_extraction_run: ai_run(other_job),
      suggestion_type: "gst_code",
      status: "proposed",
      confidence: BigDecimal("50"),
      suggested_data: { "source_type" => "BasInvoice" }
    )

    assert_not suggestion.valid?
    assert_includes suggestion.errors[:bas_ai_extraction_run], "must belong to the same BAS job"

    suggestion.bas_ai_extraction_run = ai_run(job)
    suggestion.suggestion_type = "lodgement"
    suggestion.status = "posted"
    suggestion.confidence = BigDecimal("101")

    assert_not suggestion.valid?
    assert_equal :inclusion, suggestion.errors.details[:suggestion_type].first.fetch(:error)
    assert_equal :inclusion, suggestion.errors.details[:status].first.fetch(:error)
    assert_equal :less_than_or_equal_to, suggestion.errors.details[:confidence].first.fetch(:error)
  end

  test "locked job blocks suggestion acceptance status change" do
    job = bas_job
    suggestion = ai_suggestion(job)
    job.update!(status: "locked", locked_at: Time.current, locked_by: "phase5")

    assert_not suggestion.update(status: "accepted")
    assert_includes suggestion.errors[:base], "Locked BAS jobs cannot have AI suggestions applied or reviewed"
  end

  private

  def bas_job(legal_name: "Synthetic AI Client Pty Ltd")
    BasJob.create!(
      bas_client: BasClient.create!(legal_name: legal_name),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      gst_basis: "accrual",
      reporting_method: "simpler_bas"
    )
  end

  def bas_document(job)
    document = job.documents.build(title: "Synthetic AI document", document_type: "supplier_invoice")
    document.file.attach(
      io: StringIO.new("Synthetic AI document"),
      filename: "synthetic-ai.csv",
      content_type: "text/csv"
    )
    document.save!
    document
  end

  def ai_run(job)
    BasAiExtractionRun.create!(bas_job: job, status: "completed", input_kind: "job_review")
  end

  def ai_suggestion(job)
    BasAiSuggestion.create!(
      bas_job: job,
      bas_ai_extraction_run: ai_run(job),
      suggestion_type: "summary",
      status: "proposed",
      confidence: BigDecimal("70"),
      suggested_data: {
        "summary" => "Synthetic summary",
        "unresolved_risks" => [],
        "suggested_admin_actions" => [],
        "confidence" => 70
      }
    )
  end
end
