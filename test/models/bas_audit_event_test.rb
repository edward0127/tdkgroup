require "test_helper"

class BasAuditEventTest < ActiveSupport::TestCase
  test "requires event type" do
    event = BasAuditEvent.new(bas_job: bas_job)

    assert_not event.valid?
    assert_equal :blank, event.errors.details[:event_type].first.fetch(:error)
  end

  test "requires job scope for job events" do
    event = BasAuditEvent.new(event_type: "bas_job_updated")

    assert_not event.valid?
    assert_includes event.errors[:bas_job], "must exist for job-scoped audit events"
  end

  test "allows client scoped audit events before a job exists" do
    client = BasClient.create!(legal_name: "Synthetic Client Pty Ltd")
    event = BasAuditEvent.new(
      auditable: client,
      event_type: "bas_client_created",
      actor_username: "phase1"
    )

    assert event.valid?, event.errors.full_messages.to_sentence
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
