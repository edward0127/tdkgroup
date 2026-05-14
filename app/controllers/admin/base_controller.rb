module Admin
  class BaseController < ApplicationController
    include AdminAuthentication

    layout "admin"
  end
end
