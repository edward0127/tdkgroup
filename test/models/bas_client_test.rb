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
end
