require "test_helper"

class AdminBasClientsControllerTest < ActionDispatch::IntegrationTest
  setup do
    login_as_admin
  end

  test "client with no jobs can be deleted" do
    client = create_client

    assert_difference "BasClient.count", -1 do
      delete admin_bas_client_path(client)
    end

    assert_redirected_to admin_bas_clients_path
    assert_equal "BAS client was deleted.", flash[:notice]
  end

  test "client with jobs cannot be deleted" do
    client = create_client
    create_job(client)

    assert_no_difference "BasClient.count" do
      delete admin_bas_client_path(client)
    end

    assert_redirected_to admin_bas_client_path(client)
    assert_equal BasClient::CLEANUP_DELETE_BLOCKED_MESSAGE, flash[:alert]
  end

  test "client without jobs page shows delete button" do
    client = create_client

    get admin_bas_client_path(client)

    assert_response :success
    assert_select "h2", "Danger zone"
    assert_select "button", "Delete client"
  end

  test "client with jobs page shows blocked delete explanation" do
    client = create_client
    create_job(client)

    get admin_bas_client_path(client)

    assert_response :success
    assert_select "button", text: "Delete client", count: 0
    assert_includes response.body, "Delete draft/test jobs before deleting this client."
  end

  private

  def login_as_admin
    with_modified_env("ADMIN_USERNAME" => "bas-clients-admin", "ADMIN_PASSWORD" => "secret-password") do
      post admin_login_path, params: { username: "bas-clients-admin", password: "secret-password" }
      assert_redirected_to admin_root_path
    end
  end

  def create_client
    BasClient.create!(legal_name: "Synthetic Clients Controller Client Pty Ltd")
  end

  def create_job(client)
    BasJob.create!(
      bas_client: client,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31),
      gst_basis: "cash",
      reporting_method: "simpler_bas"
    )
  end
end
