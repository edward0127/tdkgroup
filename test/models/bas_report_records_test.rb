require "test_helper"

class BasReportRecordsTest < ActiveSupport::TestCase
  test "bas adjustment validates required fields and allowlists" do
    adjustment = BasAdjustment.new(
      bas_job: bas_job,
      adjustment_type: "gst_on_sales",
      label: "Synthetic GST adjustment",
      amount: BigDecimal("5.00"),
      reason: "Synthetic review reason"
    )

    assert adjustment.valid?, adjustment.errors.full_messages.to_sentence

    adjustment.adjustment_type = "unsupported"
    adjustment.label = ""
    adjustment.amount = nil
    adjustment.reason = ""

    assert_not adjustment.valid?
    assert_equal :inclusion, adjustment.errors.details[:adjustment_type].first.fetch(:error)
    assert_equal :blank, adjustment.errors.details[:label].first.fetch(:error)
    assert_equal :blank, adjustment.errors.details[:amount].first.fetch(:error)
    assert_equal :blank, adjustment.errors.details[:reason].first.fetch(:error)
  end

  test "locked job blocks adjustment create update and destroy" do
    job = bas_job
    adjustment = BasAdjustment.create!(
      bas_job: job,
      adjustment_type: "total_sales",
      label: "Synthetic sales adjustment",
      amount: BigDecimal("10.00"),
      reason: "Synthetic reason"
    )

    job.update!(status: "locked", locked_at: Time.current, locked_by: "phase4")

    locked_adjustment = job.adjustments.build(
      adjustment_type: "gst_on_sales",
      label: "Locked adjustment",
      amount: BigDecimal("1.00"),
      reason: "Synthetic reason"
    )
    assert_not locked_adjustment.valid?
    assert_includes locked_adjustment.errors[:base], "Locked BAS jobs cannot have adjustments changed"

    assert_not adjustment.update(label: "Changed while locked")
    assert_not adjustment.destroy
  end

  test "bas report snapshot validates status json and final approval" do
    snapshot = BasReportSnapshot.new(
      bas_job: bas_job,
      status: "draft",
      totals: { "summary" => { "g1_total_sales" => "10.00" } },
      validation_errors: []
    )
    assert snapshot.valid?, snapshot.errors.full_messages.to_sentence

    snapshot.status = "posted"
    assert_not snapshot.valid?
    assert_equal :inclusion, snapshot.errors.details[:status].first.fetch(:error)

    snapshot.status = "final"
    assert_not snapshot.valid?
    assert_includes snapshot.errors[:approved_at], "must be present for final snapshots"
    assert_includes snapshot.errors[:approved_by], "must be present for final snapshots"
  end

  test "final report snapshot cannot be mutated directly" do
    snapshot = BasReportSnapshot.create!(
      bas_job: bas_job,
      status: "final",
      totals: { "summary" => { "g1_total_sales" => "10.00" } },
      validation_errors: [],
      generated_at: Time.current,
      generated_by: "phase4",
      approved_at: Time.current,
      approved_by: "phase4"
    )

    assert_not snapshot.update(totals: { "summary" => { "g1_total_sales" => "20.00" } })
    assert_includes snapshot.errors[:base], "Final report snapshots cannot be changed"
  end

  private

  def bas_job(attributes = {})
    BasJob.create!({
      bas_client: BasClient.create!(legal_name: "Synthetic Report Client Pty Ltd"),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      gst_basis: "accrual",
      reporting_method: "simpler_bas"
    }.merge(attributes))
  end
end
