require "test_helper"

class BasClientTest < ActiveSupport::TestCase
  test "validates required and allowlisted fields" do
    client = BasClient.new(
      legal_name: "Synthetic Client Pty Ltd",
      default_gst_basis: "cash",
      reporting_frequency: "quarterly",
      default_reporting_method: "simpler_bas"
    )

    assert client.valid?, client.errors.full_messages.to_sentence

    client.legal_name = ""
    assert_not client.valid?
    assert_equal :blank, client.errors.details[:legal_name].first.fetch(:error)

    client.legal_name = "Synthetic Client Pty Ltd"
    client.default_gst_basis = "hybrid"
    assert_not client.valid?
    assert_equal :inclusion, client.errors.details[:default_gst_basis].first.fetch(:error)
  end

  test "validates contact email only when present" do
    client = BasClient.new(legal_name: "Synthetic Client Pty Ltd", contact_email: "")
    assert client.valid?, client.errors.full_messages.to_sentence

    client.contact_email = "not-an-email"
    assert_not client.valid?
    assert_equal :invalid, client.errors.details[:contact_email].first.fetch(:error)
  end

  test "client without jobs is cleanup deletable" do
    client = bas_client

    assert client.cleanup_deletable?
  end

  test "client with jobs is not cleanup deletable and cannot be destroyed" do
    client = bas_client
    BasJob.create!(
      bas_client: client,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      gst_basis: "cash",
      reporting_method: "simpler_bas"
    )

    assert_not client.cleanup_deletable?
    assert_no_difference "BasClient.count" do
      assert_not client.destroy
    end
    assert_includes client.errors[:base], BasClient::CLEANUP_DELETE_BLOCKED_MESSAGE
  end

  private

  def bas_client
    BasClient.create!(legal_name: "Synthetic Client Pty Ltd")
  end
end
