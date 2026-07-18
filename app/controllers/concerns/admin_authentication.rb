require "digest"

module AdminAuthentication
  extend ActiveSupport::Concern

  def self.valid_credentials?(username, password)
    expected_username = credential_value("ADMIN_USERNAME", "admin")
    expected_password = credential_value("ADMIN_PASSWORD", "change_me")

    return false if expected_username.blank? || expected_password.blank?

    secure_compare(username, expected_username) && secure_compare(password, expected_password)
  end

  included do
    before_action :authenticate_admin!
  end

  private

  def authenticate_admin!
    return if admin_signed_in?

    session[:admin_return_to] = request.fullpath if request.get? || request.head?
    redirect_to admin_login_path, alert: "Please sign in to continue."
  end

  def admin_signed_in?
    session[:admin_authenticated] == true
  end

  def self.secure_compare(value, expected)
    ActiveSupport::SecurityUtils.secure_compare(
      Digest::SHA256.hexdigest(value.to_s),
      Digest::SHA256.hexdigest(expected.to_s)
    )
  end

  def self.credential_value(key, development_default)
    ENV[key].presence || (Rails.env.production? ? nil : development_default)
  end

  private_class_method :secure_compare, :credential_value
end
