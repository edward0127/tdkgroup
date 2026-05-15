module ApplicationHelper
  def page_title
    return tdk_t("admin.title") if controller_path.start_with?("admin/")

    @translation&.seo_title.presence || @translation&.title.presence || "TDK Group Pty Ltd"
  end

  def page_description
    @translation&.seo_description.presence ||
      "TDK Group Pty Ltd provides accounting, taxation, business advisory and immigration-related accounting services."
  end

  def canonical_url
    "#{request.base_url}#{localized_slug_path(@page&.slug || 'home', locale: current_locale)}"
  end

  def alternate_url(locale)
    "#{request.base_url}#{localized_slug_path(@page&.slug || 'home', locale: locale)}"
  end

  def nav_pages
    @nav_pages ||= begin
      CmsPage.ensure_seeded!
      CmsPage.visible_in_nav.includes(:translations)
    end
  end

  def footer_pages
    @footer_pages ||= begin
      CmsPage.ensure_seeded!
      CmsPage.visible_in_footer.includes(:translations)
    end
  end

  def page_nav_label(page, locale: current_locale)
    nav_labels = {
      "en" => {
        "home" => "Home",
        "about-us" => "About",
        "our-services" => "Services",
        "our-team" => "Our Team",
        "careers" => "Careers",
        "contact-us" => "Contact"
      },
      "zh" => {
        "home" => "首页",
        "about-us" => "关于我们",
        "our-services" => "服务",
        "our-team" => "团队",
        "careers" => "职业机会",
        "contact-us" => "联系我们"
      }
    }

    nav_labels.fetch(locale.to_s, nav_labels.fetch("en")).fetch(page.slug, page.translation_for(locale)&.title || page.slug.titleize)
  end

  def language_options
    [
      [ "English", "en" ],
      [ "中文", "zh" ]
    ]
  end

  def link_for_cms_slug(slug)
    localized_slug_path(slug, locale: current_locale)
  end

  def block_paragraphs(block)
    Array(block["body"]).presence || [ block["body"].to_s ]
  end

  def contact_value_link(value)
    text = value.to_s
    if text.match?(URI::MailTo::EMAIL_REGEXP)
      mail_to text
    elsif text.match?(/\A[\d\s()+-]+\z/)
      link_to text, "tel:#{text.gsub(/\s+/, '')}"
    else
      text
    end
  end

  def cms_asset_image_tag(key, locale: current_locale, **options)
    asset = CmsAsset.find_by(key: key)
    fallback = options.delete(:fallback)
    source = if asset&.file&.attached?
      cms_asset_source(asset)
    elsif fallback.present?
      fallback
    end
    return nil if source.blank?

    alt_text = asset&.alt_text(locale).presence || options.delete(:alt).to_s
    image_tag(source, { alt: alt_text }.merge(options))
  end

  def admin_page?
    controller_path.start_with?("admin/")
  end

  def website_json_ld
    {
      "@context" => "https://schema.org",
      "@type" => "AccountingService",
      name: "TDK Group Pty Ltd",
      alternateName: "黄金会计师事务所",
      url: request.base_url,
      telephone: "03 9890 4988",
      email: "info@tdkgroup.com.au",
      address: {
        "@type" => "PostalAddress",
        streetAddress: "1/550 Whitehorse Rd",
        addressLocality: "Surrey Hills",
        addressRegion: "VIC",
        postalCode: "3127",
        addressCountry: "AU"
      },
      areaServed: "Australia",
      availableLanguage: [ "English", "Chinese" ]
    }.to_json
  end

  def cms_asset_source(asset)
    public_host = ENV["PUBLIC_UPLOAD_ASSET_HOST"].presence
    if public_host.present? && asset.file.blob.service_name.to_s == "amazon"
      "#{public_host.to_s.chomp('/')}/#{asset.file.key}"
    else
      asset.file
    end
  end

  def tdk_logo_tag(**options)
    image_tag("tdk/tdk-logo.jpg", { alt: "TDK Group Pty Ltd" }.merge(options))
  end

  def page_template_class
    "page-template-#{@page&.template.presence || 'standard'}"
  end

  def hero_asset_key
    {
      "home" => "hero-handshake",
      "about-us" => "office-documents",
      "our-services" => "business-advisory",
      "our-services/tax-services" => "business-service",
      "our-services/business-services" => "tax-service",
      "our-services/management-consulting" => "consulting-service",
      "our-services/immigration-related-accounting-services" => "client-meeting",
      "our-team" => "business-advisory",
      "careers" => "office-documents",
      "contact-us" => "office-documents"
    }.fetch(@page&.slug, "business-advisory")
  end

  def hero_asset_fallback
    "tdk/#{hero_asset_key.tr('_', '-')}.jpg"
  end

  def service_asset_key(item)
    slug = item["slug"].presence || @page&.slug
    {
      "our-services/tax-services" => "business-service",
      "our-services/business-services" => "tax-service",
      "our-services/management-consulting" => "consulting-service",
      "our-services/immigration-related-accounting-services" => "client-meeting"
    }.fetch(slug, "business-advisory")
  end

  def service_asset_fallback(key)
    "tdk/#{key.tr('_', '-')}.jpg"
  end

  def google_maps_embed_url
    "https://www.google.com/maps?q=1%2F550%20Whitehorse%20Rd%2C%20Surrey%20Hills%20VIC%203127%2C%20Australia&output=embed"
  end

  def google_maps_open_url
    "https://www.google.com/maps/search/?api=1&query=1%2F550%20Whitehorse%20Rd%2C%20Surrey%20Hills%20VIC%203127%2C%20Australia"
  end
end
