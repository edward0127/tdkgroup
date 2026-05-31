require "test_helper"

class SeoFilesTest < ActionDispatch::IntegrationTest
  setup do
    seed_cms!
  end

  test "sitemap lists public English and Chinese pages only" do
    get "/sitemap.xml"

    assert_response :success
    assert_equal "application/xml", response.media_type
    assert_includes response.body, "<loc>#{root_url}</loc>"
    assert_includes response.body, "<loc>#{root_url}about-us</loc>"
    assert_includes response.body, "<loc>#{root_url}audit-services</loc>"
    assert_includes response.body, "<loc>#{root_url}zh/audit-services</loc>"
    assert_includes response.body, "<loc>#{root_url}zh/about-us</loc>"
    assert_no_match %r{/admin/}, response.body
    assert_no_match %r{inline_edit|preview|/edit}, response.body
  end

  test "robots excludes admin edit and preview area and points to sitemap" do
    get "/robots.txt"

    assert_response :success
    assert_includes response.body, "Disallow: /admin/"
    assert_includes response.body, "Sitemap: /sitemap.xml"
  end
end
