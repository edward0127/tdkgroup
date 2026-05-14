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
    page.translation_for(locale)&.title || page.slug.titleize
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
    return nil unless asset&.file&.attached?

    image_tag(cms_asset_source(asset), { alt: asset.alt_text(locale) }.merge(options))
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
end
