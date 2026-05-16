require "test_helper"
require "rack/test"

class AdminCmsAssetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    seed_cms!
  end

  test "admin can access asset edit page" do
    login_as_admin
    asset = CmsAsset.find_by!(key: "business-advisory")

    get edit_admin_cms_asset_path(asset)

    assert_response :success
    assert_select "h1", "Edit / Replace"
    assert_select "img.admin-asset-preview"
    assert_select "p", /updates every page/
  end

  test "non admin cannot access asset edit update or restore" do
    asset = CmsAsset.find_by!(key: "business-advisory")
    version = create_version_for(asset)

    get edit_admin_cms_asset_path(asset)
    assert_redirected_to admin_login_path

    patch admin_cms_asset_path(asset), params: {
      cms_asset: {
        alt_text_en: "Blocked",
        alt_text_zh: "Blocked",
        file: valid_image_upload
      }
    }
    assert_redirected_to admin_login_path

    post restore_version_admin_cms_asset_path(asset, version), params: { restore_alt_text: "1" }
    assert_redirected_to admin_login_path
  end

  test "admin can replace an existing asset file and creates a version" do
    login_as_admin
    asset = CmsAsset.find_by!(key: "business-advisory")
    original_key = asset.key
    original_blob = asset.file.blob
    original_alt_text_en = asset.alt_text_en
    original_alt_text_zh = asset.alt_text_zh

    assert_difference "CmsAssetVersion.count", 1 do
      patch admin_cms_asset_path(asset), params: {
        cms_asset: {
          alt_text_en: "Replacement English alt",
          alt_text_zh: "Replacement Chinese alt",
          file: replacement_image_upload
        }
      }
    end

    assert_redirected_to edit_admin_cms_asset_path(asset)
    asset.reload
    version = asset.versions.first

    assert_equal original_key, asset.key
    assert_not_equal original_blob.id, asset.file.blob.id
    assert_equal "Replacement English alt", asset.alt_text_en
    assert_equal original_blob.id, version.file.blob.id
    assert_equal original_alt_text_en, version.alt_text_en
    assert_equal original_alt_text_zh, version.alt_text_zh
    assert_equal "phase3", version.admin_identifier
  end

  test "invalid replacement does not change current file or create version" do
    login_as_admin
    asset = CmsAsset.find_by!(key: "business-advisory")
    original_blob_id = asset.file.blob.id
    original_alt_text_en = asset.alt_text_en
    original_alt_text_zh = asset.alt_text_zh

    assert_no_difference "CmsAssetVersion.count" do
      patch admin_cms_asset_path(asset), params: {
        cms_asset: {
          alt_text_en: "Should not save",
          alt_text_zh: "Should not save",
          file: invalid_upload
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select ".form-errors", /must be a JPEG, PNG, WebP or GIF image/
    asset.reload
    assert_equal original_blob_id, asset.file.blob.id
    assert_equal original_alt_text_en, asset.alt_text_en
    assert_equal original_alt_text_zh, asset.alt_text_zh
  end

  test "admin can restore previous version and keeps asset key" do
    login_as_admin
    asset = CmsAsset.find_by!(key: "business-advisory")
    original_key = asset.key
    original_blob_id = asset.file.blob.id
    original_alt_text_en = asset.alt_text_en

    patch admin_cms_asset_path(asset), params: {
      cms_asset: {
        alt_text_en: "Wrong image",
        alt_text_zh: "Wrong image zh",
        file: replacement_image_upload
      }
    }
    assert_redirected_to edit_admin_cms_asset_path(asset)
    asset.reload
    replacement_blob_id = asset.file.blob.id
    version = asset.versions.first

    assert_difference "CmsAssetVersion.count", 1 do
      post restore_version_admin_cms_asset_path(asset, version), params: { restore_alt_text: "1" }
    end

    assert_redirected_to edit_admin_cms_asset_path(asset)
    follow_redirect!
    assert_response :success
    assert_select "img.admin-asset-preview"

    asset.reload
    assert_equal original_key, asset.key
    assert_equal original_blob_id, asset.file.blob.id
    assert_not_equal replacement_blob_id, asset.file.blob.id
    assert_equal original_alt_text_en, asset.alt_text_en
  end

  test "admin can restore file without restoring alt text" do
    login_as_admin
    asset = CmsAsset.find_by!(key: "business-advisory")

    patch admin_cms_asset_path(asset), params: {
      cms_asset: {
        alt_text_en: "Keep this alt",
        alt_text_zh: "Keep this zh",
        file: replacement_image_upload
      }
    }
    asset.reload
    version = asset.versions.first

    post restore_version_admin_cms_asset_path(asset, version), params: { restore_alt_text: "0" }

    assert_redirected_to edit_admin_cms_asset_path(asset)
    asset.reload
    assert_equal version.file.blob.id, asset.file.blob.id
    assert_equal "Keep this alt", asset.alt_text_en
    assert_equal "Keep this zh", asset.alt_text_zh
  end

  test "asset deletion is blocked when asset is referenced by draft content" do
    login_as_admin
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
    login_as_admin
    asset = CmsAsset.create!(key: "phase-3-unused", alt_text_en: "Unused image")
    asset.file.attach(valid_image_upload)

    assert_difference "CmsAsset.count", -1 do
      delete admin_cms_asset_path(asset)
    end

    assert_redirected_to admin_cms_assets_path
  end

  test "protected in use asset cannot be deleted but can be replaced and restored" do
    login_as_admin
    asset = CmsAsset.find_by!(key: "business-advisory")
    original_blob_id = asset.file.blob.id

    assert_no_difference "CmsAsset.count" do
      delete admin_cms_asset_path(asset)
    end
    assert_redirected_to admin_cms_assets_path
    assert CmsAsset.exists?(asset.id)

    assert_difference "CmsAssetVersion.count", 1 do
      patch admin_cms_asset_path(asset), params: {
        cms_asset: {
          alt_text_en: "Protected replacement",
          alt_text_zh: "Protected replacement zh",
          file: replacement_image_upload
        }
      }
    end
    assert_redirected_to edit_admin_cms_asset_path(asset)

    version = asset.reload.versions.first
    post restore_version_admin_cms_asset_path(asset, version), params: { restore_alt_text: "1" }

    assert_redirected_to edit_admin_cms_asset_path(asset)
    asset.reload
    assert_equal original_blob_id, asset.file.blob.id
    assert_equal "business-advisory", asset.key
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

  def replacement_image_upload
    Rack::Test::UploadedFile.new(
      Rails.root.join("app/assets/images/tdk/cpa-liability.png").to_s,
      "image/png"
    )
  end

  def invalid_upload
    Rack::Test::UploadedFile.new(
      Rails.root.join("Gemfile").to_s,
      "text/plain"
    )
  end

  def create_version_for(asset)
    version = asset.versions.build(
      alt_text_en: asset.alt_text_en,
      alt_text_zh: asset.alt_text_zh,
      admin_identifier: "test"
    )
    version.file.attach(asset.file.blob)
    version.save!
    version
  end
end
