require "test_helper"

class TdkContentParitySyncTest < ActiveSupport::TestCase
  OPENING_PARAGRAPH = "Navigating the ever-changing and complex tax environment requires expertise and strategic planning. At TDK Group Pty Ltd, we specialize in helping individuals and businesses effectively utilize tax laws and regulations to maximize value and achieve financial goals. Our comprehensive tax services are designed to provide clarity, compliance, and long-term benefits."
  TAX_SERVICE_ITEMS = [
    "Tax planning and consulting, including real estate investment, import & export, overseas investment etc.",
    "Individual tax returns",
    "Company, trust, partnership and SMSF (Self-Managed Superannuation Fund) tax return",
    "BAS and GST Reporting",
    "Other indirect tax advice (land tax, payroll, stamp duty, payroll etc.)",
    "Assistance regarding ATO investigations and audits, including capital gains tax, GST and overseas income"
  ].freeze

  test "dry run does not change existing tax services CMS content" do
    translation = create_short_tax_services_translation!

    assert_no_changes -> { [ CmsPage.count, CmsPageTranslation.count, translation.reload.published_json, translation.reload.draft_json ] } do
      run_sync(dry_run: true)
    end
  end

  test "apply updates existing English tax services draft and published CMS content" do
    translation = create_short_tax_services_translation!

    run_sync(dry_run: false)

    expected_payload = expected_tax_services_payload
    translation.reload
    assert_equal expected_payload, translation.published_json
    assert_equal expected_payload, translation.draft_json
    assert_equal OPENING_PARAGRAPH, translation.published_json.dig("hero", "lead")
    assert_equal TAX_SERVICE_ITEMS, translation.published_json.dig("sections", 0, "bullets")
  end

  test "apply can be run twice without duplicating tax services content" do
    translation = create_short_tax_services_translation!

    run_sync(dry_run: false)
    first_payload = translation.reload.published_json.deep_dup
    first_counts = [ CmsPage.count, CmsPageTranslation.count ]

    run_sync(dry_run: false)

    translation.reload
    assert_equal first_counts, [ CmsPage.count, CmsPageTranslation.count ]
    assert_equal first_payload, translation.published_json
    assert_equal TAX_SERVICE_ITEMS, translation.published_json.dig("sections", 0, "bullets")
    assert_equal TAX_SERVICE_ITEMS.size, translation.published_json.dig("sections", 0, "bullets").uniq.size
  end

  test "filtered apply leaves unrelated CMS content unchanged" do
    tax_translation = create_short_tax_services_translation!
    unrelated_translation = create_unrelated_translation!
    unrelated_payload = unrelated_translation.published_json.deep_dup

    run_sync(dry_run: false)

    assert_equal expected_tax_services_payload, tax_translation.reload.published_json
    assert_equal unrelated_payload, unrelated_translation.reload.published_json
    assert_equal unrelated_payload, unrelated_translation.reload.draft_json
  end

  private

  def create_short_tax_services_translation!
    page = CmsPage.find_or_initialize_by(slug: "our-services/tax-services")
    page.assign_attributes(
      slug: "our-services/tax-services",
      template: "service",
      show_in_nav: false,
      show_in_footer: true,
      sort_order: 40
    )
    page.save!

    translation = page.translations.find_or_initialize_by(locale: "en")
    translation.assign_attributes(
      locale: "en",
      title: "Taxation Services",
      seo_title: "Tax Services - TDK Group Pty Ltd",
      seo_description: "Short tax services summary.",
      published_json: short_tax_services_payload,
      draft_json: short_tax_services_payload,
      published_at: Time.current
    )
    translation.save!
    translation
  end

  def create_unrelated_translation!
    page = CmsPage.find_or_initialize_by(slug: "about-us")
    page.assign_attributes(
      template: "standard",
      show_in_nav: true,
      show_in_footer: true,
      sort_order: 20
    )
    page.save!

    translation = page.translations.find_or_initialize_by(locale: "en")
    translation.assign_attributes(
      title: "About Us",
      seo_title: "Custom About Us",
      seo_description: "Custom about page content.",
      published_json: {
        "hero" => {
          "title" => "About Us",
          "lead" => "This unrelated CMS edit should not be overwritten by the tax services sync."
        },
        "sections" => []
      },
      draft_json: {
        "hero" => {
          "title" => "About Us",
          "lead" => "This unrelated CMS edit should not be overwritten by the tax services sync."
        },
        "sections" => []
      },
      published_at: Time.current
    )
    translation.save!
    translation
  end

  def short_tax_services_payload
    {
      "hero" => {
        "title" => "Taxation Services",
        "lead" => "At TDK Group, we help individuals and businesses use tax laws and regulations effectively while maintaining compliance."
      },
      "sections" => [
        {
          "kind" => "prose",
          "title" => "Our tax services include:",
          "bullets" => [ "Individual tax returns" ]
        },
        {
          "kind" => "cta",
          "title" => "Contact us to get started today",
          "body" => "Contact us to get started today",
          "label" => "Contact Us",
          "slug" => "contact-us"
        }
      ]
    }
  end

  def expected_tax_services_payload
    page_data = TdkOriginalContent.pages.find { |page| page.fetch(:slug) == "our-services/tax-services" }
    JSON.parse(JSON.generate(page_data.fetch(:en).fetch(:content)))
  end

  def run_sync(dry_run:, slugs: [ "our-services/tax-services" ])
    TdkContentParitySync.new(dry_run: dry_run, io: StringIO.new, slugs: slugs).call
  end
end
