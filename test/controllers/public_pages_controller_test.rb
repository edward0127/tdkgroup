require "test_helper"
require "nokogiri"

class PublicPagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    seed_cms!
  end

  test "homepage renders with seo and language alternates" do
    get root_url

    assert_response :success
    assert_select "title", "TDK Group Pty Ltd – 黄金会计师事务所"
    assert_select "h1", /Empowering Businesses with Expert Taxation and Consulting Services/
    assert_select "nav.site-nav a:first-child", text: "Home"
    assert_select "nav.site-nav a", text: "Careers", count: 0
    assert_select ".site-nav__dropdown a", text: "Tax Services"
    assert_select ".site-nav__dropdown a", text: "Business Services"
    assert_select ".site-nav__dropdown a", text: "Management Consulting"
    assert_select ".site-nav__dropdown a", text: "Immigration Related Accounting Services"
    assert_select "nav.site-nav", text: /TDK Group Pty Ltd/, count: 0
    logos = css_select("img.brand-logo__image")
    assert_equal 2, logos.size
    logos.each do |logo|
      assert_includes logo["src"], "/assets/tdk/tdk-logo"
      refute_includes logo["src"], "/rails/active_storage"
    end
    assert_select ".cms-editor-toolbar", count: 0
    assert_select ".cms-image-picker", count: 0
    assert_select "a[href^='/admin']", count: 0
    assert_select "form[action^='/admin']", count: 0
    assert_no_match "Edit / Replace", response.body
    assert_select "meta[name='description']"
    assert_select "link[rel='icon'][href='/favicon.ico?v=tdkmark-20260531'][sizes='any']"
    assert_select "link[rel='icon'][href='/favicon.svg?v=tdkmark-20260531'][type='image/svg+xml']"
    assert_select "link[rel='icon'][href='/favicon-32x32.png?v=tdkmark-20260531'][sizes='32x32']"
    assert_select "link[rel='icon'][href='/favicon-48x48.png?v=tdkmark-20260531'][sizes='48x48']"
    assert_select "link[rel='apple-touch-icon'][href='/apple-touch-icon.png?v=tdkmark-20260531'][sizes='180x180']"
    assert_select "link[rel='canonical'][href='#{root_url}']"
    assert_select "link[rel='alternate'][hreflang='zh-CN'][href='#{zh_root_url}']"
    assert_select "form[action='#{language_preference_path}']"
  end

  test "original old-site English content is restored across public pages" do
    {
      "/" => [
        "Trusted by Businesses and Individuals, Empowered by Expertise",
        "We are more than an accounting firm — we are strategic partners in driving success.",
        "Tax Services: Individual and business tax returns, tax planning, BAS and GST preparation, and assistance with ATO investigations."
      ],
      "/about-us" => [
        "Founded with a vision to deliver exceptional accounting and consulting services",
        "Our History",
        "At TDK Group, we are driven by professional and ethical standards."
      ],
      "/our-services" => [
        "At TDK Group Pty Ltd, we adhere to the highest professional and ethical standards",
        "Taxation Services",
        "Business Accounting Services"
      ],
      "/our-services/tax-services" => [
        "Our tax services include:",
        "Tax planning and consulting, including real estate investment, import & export, overseas investment etc.",
        "Assistance regarding ATO investigations and audits, including capital gains tax, GST and overseas income"
      ],
      "/our-services/business-services" => [
        "Our business services include:",
        "Professional and practical accounting training tailored to your team’s needs and consulting",
        "Business and Entity Registration (Companies, trusts, partnerships, and SMSFs, including ABN, GST, TFN, and PAYG)"
      ],
      "/our-services/management-consulting" => [
        "Our management consulting services include:",
        "Risk management, business benchmarking and reviews",
        "Business sale and purchase advisory (including vendor’s statement, Form 2, value and risk assessment)"
      ],
      "/our-services/immigration-related-accounting-services" => [
        "Navigating the financial requirements for immigration applications can be complex and time-consuming.",
        "Business Skilled Migration Visa (188A, 188B, 188C/132):",
        "Temporary Work (Skilled) Visa 457—-processing of related financial reporting and auditing required by visa application."
      ],
      "/audit-services" => [
        "We offer risk oriented audit service",
        "Reviewing service;",
        "Audit on accounts and financial report in accordance with Corporation Act 2011;"
      ],
      "/our-team" => [
        "Tom Huang",
        "Professional Qualifications:",
        "Certified Practicing Accountant (CPA)",
        "Tom Huang is an experienced and highly qualified professional with over 20 years of expertise in accounting."
      ],
      "/careers" => [
        "At TDK Group, we believe in empowering businesses and individuals to achieve financial success.",
        "Internship opportunities",
        "*Applicants who are fluent in Mandarin are highly encouraged to apply."
      ],
      "/contact-us" => [
        "We’re here to help! Reach out to us using the details below",
        "03 9890 4988",
        "info@tdkgroup.com.au",
        "Monday to Friday, 9:30 AM – 6:00 PM"
      ]
    }.each do |path, snippets|
      get path

      assert_response :success, "#{path} should render"
      text = page_text
      snippets.each do |snippet|
        assert_includes text, snippet, "#{path} should include original text: #{snippet}"
      end
    end
  end

  test "footer uses old-site Company Services Resources groups" do
    get root_url

    assert_response :success
    assert_select ".site-footer__panel h2", text: "Company"
    assert_select ".site-footer__panel h2", text: "Services"
    assert_select ".site-footer__panel h2", text: "Resources"
    assert_select ".site-footer__links a", text: "Careers"
    assert_select ".site-footer__links a", text: "Audit Services"
    assert_select ".site-footer__links span", text: "FAQs"
  end

  test "inner page browser title follows old-site pattern" do
    get "/about-us"

    assert_response :success
    assert_select "title", "About Us – TDK Group Pty Ltd"
  end

  test "all public pages render required seo metadata" do
    public_paths.each do |path|
      get path

      assert_response :success, "#{path} should render"
      assert css_select("title").first.text.present?, "#{path} should have a title"
      assert css_select("meta[name='description'][content]").first["content"].present?, "#{path} should have a meta description"
      assert_select "meta[property='og:title'][content]"
      assert_select "meta[property='og:description'][content]"
      assert_select "link[rel='canonical'][href]"
      assert_select "link[rel='alternate'][hreflang='en-AU'][href]"
      assert_select "link[rel='alternate'][hreflang='zh-CN'][href]"
    end
  end

  test "language selector posts to equivalent page" do
    get "/about-us"

    assert_response :success
    assert css_select("form.language-selector__form input[name='slug'][value='about-us']").any?
    assert css_select("form.language-selector__form input[name='locale'][value='zh']").any?
    assert_select ".site-header__actions .language-selector"
    assert_select ".mobile-header__actions form.mobile-language-switcher__form input[name='locale'][value='zh']", count: 1
    assert_select ".mobile-header__actions .mobile-language-switcher__button", text: "\u4e2d\u6587"
    assert_select ".mobile-menu__panel .language-selector", count: 0

    get "/zh/contact-us"

    assert_response :success
    assert css_select("form.language-selector__form input[name='slug'][value='contact-us']").any?
    assert css_select("form.language-selector__form input[name='locale'][value='en']").any?
    assert_select ".site-header__actions .language-selector"
    assert_select ".mobile-header__actions form.mobile-language-switcher__form input[name='locale'][value='en']", count: 1
    assert_select ".mobile-header__actions .mobile-language-switcher__button", text: "EN"
    assert_select ".mobile-menu__panel .language-selector", count: 0
  end

  test "Chinese homepage renders short navigation labels and local logo" do
    get zh_root_url

    assert_response :success
    assert_select "nav.site-nav a:first-child", text: "首页"
    assert_select ".site-nav__dropdown a", text: "税务服务"
    assert_select "img.brand-logo__image[src*='/assets/tdk/tdk-logo']"
    assert_no_match "tdkgroup.com.au/wp-content/uploads", response.body
  end

  test "key English public pages render" do
    [
      "/about-us",
      "/our-services",
      "/our-services/tax-services",
      "/our-services/business-services",
      "/our-services/management-consulting",
      "/our-services/immigration-related-accounting-services",
      "/audit-services",
      "/our-team",
      "/careers",
      "/contact-us"
    ].each do |path|
      get path

      assert_response :success, "#{path} should render"
      assert_select "main"
    end
  end

  test "contact page renders local assets and embedded map" do
    get "/contact-us"

    assert_response :success
    assert_select "img.brand-logo__image[src*='/assets/tdk/tdk-logo']"
    assert_select "iframe[title='TDK Group office map']"
    assert_select "a[href*='google.com/maps/search'][href*='TDK%20Group']"
    assert_no_match "tdkgroup.com.au/wp-content/uploads", response.body
  end

  test "public pages do not hotlink old WordPress uploads" do
    public_paths.each do |path|
      get path

      assert_response :success
      assert_no_match "tdkgroup.com.au/wp-content/uploads", response.body
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
      "/zh/audit-services",
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

    get "/services-2/audit-service"
    assert_redirected_to "/audit-services"
  end

  private

  def page_text
    Nokogiri::HTML(response.body).text.gsub(/\s+/, " ").strip
  end

  def public_paths
    [
      "/",
      "/about-us",
      "/our-services",
      "/our-services/tax-services",
      "/our-services/business-services",
      "/our-services/management-consulting",
      "/our-services/immigration-related-accounting-services",
      "/audit-services",
      "/our-team",
      "/careers",
      "/contact-us",
      "/zh",
      "/zh/about-us",
      "/zh/our-services",
      "/zh/our-services/tax-services",
      "/zh/our-services/business-services",
      "/zh/our-services/management-consulting",
      "/zh/our-services/immigration-related-accounting-services",
      "/zh/audit-services",
      "/zh/our-team",
      "/zh/careers",
      "/zh/contact-us"
    ]
  end
end
