require "test_helper"

class PublicPagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    seed_cms!
  end

  test "homepage renders with seo and language alternates" do
    get root_url

    assert_response :success
    assert_select "h1", /Expert taxation/
    assert_select "meta[name='description']"
    assert_select "link[rel='canonical'][href='#{root_url}']"
    assert_select "link[rel='alternate'][hreflang='zh-CN'][href='#{zh_root_url}']"
    assert_select "form[action='#{language_preference_path}']"
  end

  test "key English public pages render" do
    [
      "/about-us",
      "/our-services",
      "/our-services/tax-services",
      "/our-services/business-services",
      "/our-services/management-consulting",
      "/our-services/immigration-related-accounting-services",
      "/our-team",
      "/careers",
      "/contact-us"
    ].each do |path|
      get path

      assert_response :success, "#{path} should render"
      assert_select "main"
    end
  end

  test "key Chinese public pages render" do
    [
      "/zh",
      "/zh/about-us",
      "/zh/our-services",
      "/zh/our-services/tax-services",
      "/zh/our-services/business-services",
      "/zh/our-services/management-consulting",
      "/zh/our-services/immigration-related-accounting-services",
      "/zh/our-team",
      "/zh/careers",
      "/zh/contact-us"
    ].each do |path|
      get path

      assert_response :success, "#{path} should render"
      assert_select "html[lang='zh']"
    end
  end

  test "browser language fallback sends first Chinese visitor to Chinese homepage" do
    get root_url, headers: { "HTTP_ACCEPT_LANGUAGE" => "zh-CN,zh;q=0.9,en;q=0.8" }

    assert_redirected_to zh_root_url
  end

  test "explicit language choice is persisted and redirects to equivalent page" do
    post language_preference_path, params: { locale: "zh", slug: "about-us" }

    assert_redirected_to "/zh/about-us"
    assert_match "tdk_locale", response.headers["Set-Cookie"]

    follow_redirect!
    assert_response :success
    assert_select "html[lang='zh']"
  end

  test "legacy routes redirect to clean pages" do
    get "/home"
    assert_redirected_to "/"

    get "/zh/home-2"
    assert_redirected_to "/zh"

    get "/zh/%E5%85%AC%E5%8F%B8%E7%AE%80%E4%BB%8B"
    assert_redirected_to "/zh/about-us"

    get "/author/tdkgroup"
    assert_redirected_to "/"
  end
end
