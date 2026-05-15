require "test_helper"
require "rack/test"

class AdminCmsPagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    seed_cms!
    login_as_admin
  end

  test "non admin cannot access inline edit mode" do
    reset!
    page = CmsPage.find_by!(slug: "about-us")

    get inline_edit_admin_cms_page_path(page, locale: "en")

    assert_redirected_to admin_login_path
  end

  test "non admin cannot access draft preview" do
    reset!
    page = CmsPage.find_by!(slug: "about-us")

    get preview_admin_cms_page_path(page, locale: "en")

    assert_redirected_to admin_login_path
  end

  test "admin can access inline edit mode" do
    page = CmsPage.find_by!(slug: "about-us")

    get inline_edit_admin_cms_page_path(page, locale: "en")

    assert_response :success
    assert_select ".cms-editor-toolbar", /Inline CMS edit/
    assert_select "textarea[name='fields[hero.title]']"
    assert_select ".cms-image-picker"
    assert_select "meta[name='robots'][content='noindex,nofollow']"
  end

  test "draft preview is noindexed" do
    page = CmsPage.find_by!(slug: "about-us")

    get preview_admin_cms_page_path(page, locale: "en")

    assert_response :success
    assert_select ".cms-preview-banner", /Draft preview/
    assert_select "meta[name='robots'][content='noindex,nofollow']"
    assert_select "link[rel='canonical']", count: 0
  end

  test "inline draft save previews and publishes without overwriting Chinese content" do
    page = CmsPage.includes(:translations).find_by!(slug: "about-us")
    english = page.translation_for("en")
    chinese = page.translation_for("zh")
    published_title = english.published_json.dig("hero", "title")
    chinese_draft_title = chinese.draft_content.dig("hero", "title")
    draft_title = "Phase 2 inline draft title"

    patch inline_update_admin_cms_page_path(page, locale: "en"), params: {
      fields: {
        "hero.title" => draft_title,
        "sections.0.body.0" => "Phase 2 inline paragraph"
      }
    }

    assert_redirected_to inline_edit_admin_cms_page_path(page, locale: "en")
    assert_equal draft_title, english.reload.draft_content.dig("hero", "title")
    assert_equal published_title, english.reload.published_json.dig("hero", "title")
    assert_equal chinese_draft_title, chinese.reload.draft_content.dig("hero", "title")

    get "/about-us"
    assert_response :success
    assert_includes response.body, published_title
    refute_includes response.body, draft_title

    get preview_admin_cms_page_path(page, locale: "en")
    assert_response :success
    assert_select ".cms-preview-banner", /Draft preview/
    assert_includes response.body, draft_title

    post publish_admin_cms_page_path(page), params: { locale: "en" }
    assert_redirected_to edit_admin_cms_page_path(page)

    get "/about-us"
    assert_response :success
    assert_includes response.body, draft_title

    get "/zh/about-us"
    assert_response :success
    refute_includes response.body, draft_title
    assert_equal chinese_draft_title, chinese.reload.draft_content.dig("hero", "title")
  end

  test "admin can upload and replace a CMS image in draft content" do
    page = CmsPage.includes(:translations).find_by!(slug: "about-us")
    english = page.translation_for("en")
    new_key = "phase-2-inline-hero"

    patch inline_update_admin_cms_page_path(page, locale: "en"), params: {
      image_fields: {
        "hero.image_key" => {
          selected_key: "office-documents",
          new_key: new_key,
          alt_text_en: "Phase 2 uploaded hero",
          alt_text_zh: "Phase 2 uploaded hero zh",
          file: valid_image_upload
        }
      }
    }

    assert_redirected_to inline_edit_admin_cms_page_path(page, locale: "en")
    asset = CmsAsset.find_by!(key: new_key)
    assert asset.file.attached?
    assert_equal "Phase 2 uploaded hero", asset.alt_text_en
    assert_equal new_key, english.reload.draft_content.dig("hero", "image_key")

    post publish_admin_cms_page_path(page), params: { locale: "en" }
    get "/about-us"

    assert_response :success
    assert_select "img.hero-media__image[alt='Phase 2 uploaded hero']"
  end

  test "invalid inline image upload is rejected" do
    page = CmsPage.includes(:translations).find_by!(slug: "about-us")
    english = page.translation_for("en")

    assert_no_difference "CmsAsset.count" do
      patch inline_update_admin_cms_page_path(page, locale: "en"), params: {
        image_fields: {
          "hero.image_key" => {
            selected_key: "office-documents",
            new_key: "phase-2-invalid-image",
            alt_text_en: "Invalid upload",
            alt_text_zh: "Invalid upload zh",
            file: invalid_file_upload
          }
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select ".flash--alert", /JPEG, PNG, WebP or GIF/
    refute_equal "phase-2-invalid-image", english.reload.draft_content.dig("hero", "image_key")
  end

  test "admin can save and publish draft content" do
    page = CmsPage.includes(:translations).find_by!(slug: "about-us")
    english = page.translation_for("en")
    chinese = page.translation_for("zh")
    draft = english.draft_content.deep_dup
    draft["hero"]["title"] = "Published Phase 1 About TDK"

    patch admin_cms_page_path(page), params: {
      cms_page: {
        template: page.template,
        show_in_nav: page.show_in_nav,
        show_in_footer: page.show_in_footer,
        sort_order: page.sort_order
      },
      translations: {
        en: {
          title: english.title,
          seo_title: english.seo_title,
          seo_description: english.seo_description,
          draft_json: JSON.pretty_generate(draft)
        },
        zh: {
          title: chinese.title,
          seo_title: chinese.seo_title,
          seo_description: chinese.seo_description,
          draft_json: JSON.pretty_generate(chinese.draft_content)
        }
      }
    }

    assert_redirected_to edit_admin_cms_page_path(page)

    post publish_admin_cms_page_path(page), params: { locale: "en" }
    assert_redirected_to edit_admin_cms_page_path(page)

    get "/about-us"
    assert_response :success
    assert_includes response.body, "Published Phase 1 About TDK"
  end

  test "admin sees invalid draft JSON errors" do
    page = CmsPage.includes(:translations).find_by!(slug: "about-us")
    english = page.translation_for("en")
    chinese = page.translation_for("zh")

    patch admin_cms_page_path(page), params: {
      cms_page: {
        template: page.template,
        show_in_nav: page.show_in_nav,
        show_in_footer: page.show_in_footer,
        sort_order: page.sort_order
      },
      translations: {
        en: {
          title: english.title,
          seo_title: english.seo_title,
          seo_description: english.seo_description,
          draft_json: "{ invalid"
        },
        zh: {
          title: chinese.title,
          seo_title: chinese.seo_title,
          seo_description: chinese.seo_description,
          draft_json: JSON.pretty_generate(chinese.draft_content)
        }
      }
    }

    assert_response :unprocessable_entity
    assert_select ".flash--alert", /Draft JSON is invalid/
  end

  private

  def login_as_admin
    with_modified_env("ADMIN_USERNAME" => "phase1", "ADMIN_PASSWORD" => "secret-password") do
      post admin_login_path, params: { username: "phase1", password: "secret-password" }
      assert_redirected_to admin_root_path
    end
  end

  def valid_image_upload
    Rack::Test::UploadedFile.new(
      Rails.root.join("app/assets/images/tdk/tax-service.jpg").to_s,
      "image/jpeg"
    )
  end

  def invalid_file_upload
    Rack::Test::UploadedFile.new(
      Rails.root.join("README.md").to_s,
      "text/plain"
    )
  end
end
