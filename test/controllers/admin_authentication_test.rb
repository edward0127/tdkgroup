require "test_helper"

class AdminAuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    seed_cms!
  end

  test "non admin visitors cannot access admin pages" do
    get admin_root_path

    assert_redirected_to admin_login_path
  end

  test "admin login renders static local logo" do
    get admin_login_path

    assert_response :success
    assert_select "img.admin-login-logo[src*='/assets/tdk/tdk-logo']"
    assert_no_match "/rails/active_storage", css_select("img.admin-login-logo").first["src"]
  end

  test "admin can login and logout" do
    with_modified_env("ADMIN_USERNAME" => "phase1", "ADMIN_PASSWORD" => "secret-password") do
      get admin_login_path
      assert_response :success

      post admin_login_path, params: { username: "phase1", password: "secret-password" }
      assert_redirected_to admin_root_path

      follow_redirect!
      assert_response :success
      assert_select "h1", /CMS dashboard/

      delete admin_logout_path
      assert_redirected_to admin_login_path

      get admin_root_path
      assert_redirected_to admin_login_path
    end
  end

  test "invalid admin credentials are rejected" do
    with_modified_env("ADMIN_USERNAME" => "phase1", "ADMIN_PASSWORD" => "secret-password") do
      post admin_login_path, params: { username: "phase1", password: "wrong" }

      assert_response :unauthorized
      assert_select ".flash--alert"
    end
  end
end
