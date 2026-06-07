module Admin
  class BaseController < ApplicationController
    include AdminAuthentication

    layout "admin"

    helper_method :current_admin_identifier

    private

    def current_admin_identifier
      session[:admin_username].presence || "admin"
    end
  end
end
