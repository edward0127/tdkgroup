require "test_helper"
require "rack/test"

class AdminCmsAssetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    seed_cms!
    login_as_admin
  end

  test "asset deletion is blocked when asset is referenced by draft content" do
    asset = CmsAsset.create!(key: "phase-3-referenced", alt_text_en: "Referenced image")
    asset.file.attach(valid_image_upload)

    page = CmsPage.includes(:translations).find_by!(slug: "about-us")
    translation = page.translation_for("en")
    draft = translation.draft_content.deep_dup
    draft["hero"]["image_key"] = asset.key
    translation.update!(draft_json: draft)

    assert_no_difference "CmsAsset.count" do
      delete admin_cms_asset_path(asset)
    end

    assert_redirected_to admin_cms_assets_path
    follow_redirect!
    assert_select ".flash--alert", /in use/
    assert CmsAsset.exists?(asset.id)
  end

  test "unused uploaded asset can be deleted" do
    asset = CmsAsset.create!(key: "phase-3-unused", alt_text_en: "Unused image")
    asset.file.attach(valid_image_upload)

    assert_difference "CmsAsset.count", -1 do
      delete admin_cms_asset_path(asset)
    end

    assert_redirected_to admin_cms_assets_path
  end

  private

  def login_as_admin
    with_modified_env("ADMIN_USERNAME" => "phase3", "ADMIN_PASSWORD" => "secret-password") do
      post admin_login_path, params: { username: "phase3", password: "secret-password" }
      assert_redirected_to admin_root_path
    end
  end

  def valid_image_upload
    Rack::Test::UploadedFile.new(
      Rails.root.join("app/assets/images/tdk/tax-service.jpg").to_s,
      "image/jpeg"
    )
  end
end
