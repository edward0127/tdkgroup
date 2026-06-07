require "test_helper"

class BasJobTest < ActiveSupport::TestCase
  test "defaults gst basis and reporting method from client" do
    client = bas_client(default_gst_basis: "cash", default_reporting_method: "simpler_bas")
    job = BasJob.new(
      bas_client: client,
      period_start: Date.new(2025, 7, 1),
      period_end: Date.new(2025, 9, 30)
    )

    assert job.valid?, job.errors.full_messages.to_sentence
    assert_equal "cash", job.gst_basis
    assert_equal "simpler_bas", job.reporting_method
    assert_equal "FY2026 Q1", job.quarter_label
  end

  test "validates period order and allowlists" do
    job = BasJob.new(
      bas_client: bas_client,
      period_start: Date.new(2026, 3, 31),
      period_end: Date.new(2026, 1, 1),
      status: "unknown_status",
      gst_basis: "hybrid",
      reporting_method: "extended"
    )

    assert_not job.valid?
    assert_includes job.errors[:period_start], "must be before or equal to period end"
    assert_equal :inclusion, job.errors.details[:status].first.fetch(:error)
    assert_equal :inclusion, job.errors.details[:gst_basis].first.fetch(:error)
    assert_equal :inclusion, job.errors.details[:reporting_method].first.fetch(:error)
  end

  test "detects locked jobs" do
    job = BasJob.new(status: "locked")

    assert job.locked?
  end

  private

  def bas_client(attributes = {})
    BasClient.create!({
      legal_name: "Synthetic Client Pty Ltd"
    }.merge(attributes))
  end
end
