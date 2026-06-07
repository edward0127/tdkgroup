require "test_helper"

class BasQueryTest < ActiveSupport::TestCase
  test "validates required and allowlisted fields" do
    query = BasQuery.new(bas_job: bas_job, title: "Missing receipt", query_type: "missing_receipt")
    assert query.valid?, query.errors.full_messages.to_sentence

    query.title = ""
    query.status = "closed"
    query.query_type = "unknown"

    assert_not query.valid?
    assert_equal :blank, query.errors.details[:title].first.fetch(:error)
    assert_equal :inclusion, query.errors.details[:status].first.fetch(:error)
    assert_equal :inclusion, query.errors.details[:query_type].first.fetch(:error)
  end

  test "requires resolution notes and timestamps resolved queries" do
    query = BasQuery.new(bas_job: bas_job, title: "GST treatment unclear", status: "resolved")

    assert_not query.valid?
    assert_includes query.errors[:resolution_notes], "must be provided when resolving or dismissing a query"

    query.resolution_notes = "Synthetic resolution notes."
    assert query.save, query.errors.full_messages.to_sentence
    assert query.resolved_at.present?
  end

  private

  def bas_job
    @bas_job ||= BasJob.create!(
      bas_client: BasClient.create!(legal_name: "Synthetic Client Pty Ltd"),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31)
    )
  end
end
