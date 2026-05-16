module Admin
  class CmsAssetsController < BaseController
    def index
      @asset = CmsAsset.new
      @assets = CmsAsset.with_attached_file.order(:key)
      @in_use_asset_keys = CmsAsset.in_use_keys
    end

    def edit
      set_asset
      set_versions
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

    def update
      set_asset
      attributes = asset_update_params

      if @asset.replace_file(
        replacement_file: attributes[:file],
        alt_text_en: attributes[:alt_text_en],
        alt_text_zh: attributes[:alt_text_zh],
        admin_identifier: current_admin_identifier
      )
        redirect_to edit_admin_cms_asset_path(@asset), notice: asset_update_notice(attributes[:file])
      else
        render_invalid_edit
      end
    end

    def restore
      set_asset
      version = @asset.versions.find(params[:version_id])

      if @asset.restore_version(
        version,
        restore_alt_text: restore_alt_text?,
        admin_identifier: current_admin_identifier
      )
        redirect_to edit_admin_cms_asset_path(@asset), notice: "Asset restored. The asset key stayed \"#{@asset.key}\"."
      else
        render_invalid_edit
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

    def set_asset
      @asset = CmsAsset.with_attached_file.find(params[:id])
    end

    def set_versions
      @versions = @asset.versions.with_attached_file
    end

    def asset_params
      params.require(:cms_asset).permit(:key, :alt_text_en, :alt_text_zh, :file)
    end

    def asset_update_params
      params.require(:cms_asset).permit(:alt_text_en, :alt_text_zh, :file)
    end

    def restore_alt_text?
      ActiveModel::Type::Boolean.new.cast(params.fetch(:restore_alt_text, true))
    end

    def current_admin_identifier
      session[:admin_username].presence
    end

    def asset_update_notice(file)
      if file.present?
        "Asset replaced. The asset key stayed \"#{@asset.key}\"."
      else
        "Asset alt text updated."
      end
    end

    def render_invalid_edit
      messages = @asset.errors.full_messages
      @asset.reload
      messages.each { |message| @asset.errors.add(:base, message) }
      set_versions
      flash.now[:alert] = "Asset could not be updated."
      render :edit, status: :unprocessable_entity
    end
  end
end
