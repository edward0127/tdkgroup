require "test_helper"

class AdminBasClientsControllerTest < ActionDispatch::IntegrationTest
  setup do
    login_as_admin
  end

  test "index shows client list" do
    client = create_client(
      legal_name: "Synthetic Index Client Pty Ltd",
      trading_name: "Synthetic Index Trading",
      abn: "12 345 678 901",
      contact_email: "index-client@example.test"
    )
    create_job(client)

    get admin_bas_clients_path

    assert_response :success
    assert_select "h1", "Clients"
    assert_select "a[href='#{admin_bas_client_path(client)}']", text: client.legal_name
    assert_select "td", text: client.trading_name
    assert_select "td", text: client.abn
    assert_select "td", text: client.contact_email
    assert_select "td", text: "1"
    assert_select "a[href='#{edit_admin_bas_client_path(client)}']", text: "Edit"
  end

  test "show displays client details and related jobs" do
    client = create_client(
      legal_name: "Synthetic Details Client Pty Ltd",
      trading_name: "Synthetic Details Trading",
      abn: "98 765 432 109",
      contact_name: "Synthetic Contact",
      contact_email: "details-client@example.test",
      default_gst_basis: "cash",
      default_reporting_method: "simpler_bas",
      notes: "Synthetic internal client notes"
    )
    job = create_job(client, status: "collecting_materials")

    get admin_bas_client_path(client)

    assert_response :success
    assert_select "h1", client.primary_name
    assert_includes response.body, "Trading name: #{client.trading_name}"
    assert_includes response.body, "ABN: #{client.formatted_abn}"
    assert_includes response.body, client.legal_name
    assert_includes response.body, client.trading_name
    assert_includes response.body, client.abn
    assert_includes response.body, client.contact_name
    assert_includes response.body, client.contact_email
    assert_includes response.body, "Cash"
    assert_includes response.body, "Simpler bas"
    assert_includes response.body, client.notes
    assert_select "h2", "Related BAS jobs"
    assert_select "a[href='#{admin_bas_job_path(job)}']", text: job.period_label
    assert_select "td", text: job.status.humanize
    assert_select "a[href='#{admin_bas_job_path(job)}']", text: "Open job"
  end

  test "edit form loads" do
    client = create_client(legal_name: "Synthetic Editable Client Pty Ltd")

    get edit_admin_bas_client_path(client)

    assert_response :success
    assert_select "h1", "Edit client"
    assert_select "form[action='#{admin_bas_client_path(client)}']"
    assert_select "input[name='bas_client[legal_name]'][value='#{client.legal_name}']"
  end

  test "update changes legal name trading name and contact fields" do
    client = create_client

    patch admin_bas_client_path(client), params: {
      bas_client: {
        legal_name: "Synthetic Updated Client Pty Ltd",
        trading_name: "Synthetic Updated Trading",
        contact_name: "Updated Contact",
        contact_email: "updated-client@example.test"
      }
    }

    assert_redirected_to admin_bas_client_path(client)
    assert_equal "BAS client was updated.", flash[:notice]
    client.reload
    assert_equal "Synthetic Updated Client Pty Ltd", client.legal_name
    assert_equal "Synthetic Updated Trading", client.trading_name
    assert_equal "Updated Contact", client.contact_name
    assert_equal "updated-client@example.test", client.contact_email
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

  test "blocked deletion shows clear alert" do
    client = create_client
    create_job(client)

    delete admin_bas_client_path(client)
    follow_redirect!

    assert_response :success
    assert_includes response.body, BasClient::CLEANUP_DELETE_BLOCKED_MESSAGE
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
    assert_includes response.body, BasClient::CLEANUP_DELETE_BLOCKED_MESSAGE
  end

  private

  def login_as_admin
    with_modified_env("ADMIN_USERNAME" => "bas-clients-admin", "ADMIN_PASSWORD" => "secret-password") do
      post admin_login_path, params: { username: "bas-clients-admin", password: "secret-password" }
      assert_redirected_to admin_root_path
    end
  end

  def create_client(attributes = {})
    BasClient.create!({
      legal_name: "Synthetic Clients Controller Client Pty Ltd"
    }.merge(attributes))
  end

  def create_job(client, attributes = {})
    BasJob.create!(
      {
        bas_client: client,
        period_start: Date.new(2026, 1, 1),
        period_end: Date.new(2026, 3, 31),
        gst_basis: "cash",
        reporting_method: "simpler_bas"
      }.merge(attributes)
    )
  end
end
