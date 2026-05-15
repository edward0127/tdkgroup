module Admin
  class CmsAssetsController < BaseController
    def index
      @asset = CmsAsset.new
      @assets = CmsAsset.with_attached_file.order(:key)
      @in_use_asset_keys = CmsAsset.in_use_keys
    end

    def create
      @asset = CmsAsset.new(asset_params)

      if @asset.save
        redirect_to admin_cms_assets_path, notice: "Asset uploaded."
      else
        @assets = CmsAsset.with_attached_file.order(:key)
        @in_use_asset_keys = CmsAsset.in_use_keys
        flash.now[:alert] = "Asset could not be uploaded."
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      asset = CmsAsset.find(params[:id])

      if CmsAsset.in_use_keys.include?(asset.key)
        redirect_to admin_cms_assets_path, alert: "Asset \"#{asset.key}\" is in use by CMS content or protected seed assets and was not deleted."
        return
      end

      asset.destroy
      redirect_to admin_cms_assets_path, notice: "Asset removed."
    end

    private

    def asset_params
      params.require(:cms_asset).permit(:key, :alt_text_en, :alt_text_zh, :file)
    end
  end
end
