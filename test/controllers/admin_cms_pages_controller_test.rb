require "test_helper"

class AdminCmsPagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    seed_cms!
    login_as_admin
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
end
