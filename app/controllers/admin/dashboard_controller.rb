module Admin
  class DashboardController < BaseController
    def show
      @pages = CmsPage.includes(:translations).ordered
      @assets = CmsAsset.with_attached_file.order(:key)
    end
  end
end
