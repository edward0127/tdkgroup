module Admin
  class SessionsController < ApplicationController
    layout "admin_login"

    def new
      redirect_to admin_root_path if session[:admin_authenticated] == true
    end

    def create
      if AdminAuthentication.valid_credentials?(params[:username], params[:password])
        session[:admin_authenticated] = true
        redirect_to(session.delete(:admin_return_to).presence || admin_root_path, notice: "Signed in.")
      else
        flash.now[:alert] = "Username or password is incorrect."
        render :new, status: :unauthorized
      end
    end

    def destroy
      reset_session
      redirect_to admin_login_path, notice: "Signed out."
    end
  end
end
