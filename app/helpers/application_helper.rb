module ApplicationHelper
  def page_title
    return tdk_t("admin.title") if controller_path.start_with?("admin/")
    return "TDK Group Pty Ltd – 黄金会计师事务所" if @page&.slug == "home"

    title = @translation&.title.presence || "TDK Group Pty Ltd"
    site_name = current_locale == "zh" ? "黄金会计师事务所" : "TDK Group Pty Ltd"
    "#{title} – #{site_name}"
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
    slug = page.respond_to?(:slug) ? page.slug : page.to_s
    nav_labels = {
      "en" => {
        "home" => "Home",
        "about-us" => "About Us",
        "our-services" => "Our Services",
        "our-services/tax-services" => "Tax Services",
        "our-services/business-services" => "Business Services",
        "our-services/management-consulting" => "Management Consulting",
        "our-services/immigration-related-accounting-services" => "Immigration Related Accounting Services",
        "audit-services" => "Audit Services",
        "our-team" => "Our Team",
        "careers" => "Careers",
        "contact-us" => "Contact Us"
      },
      "zh" => {
        "home" => "首页",
        "about-us" => "关于我们",
        "our-services" => "我们的服务",
        "our-services/tax-services" => "税务服务",
        "our-services/business-services" => "商业会计服务",
        "our-services/management-consulting" => "管理咨询",
        "our-services/immigration-related-accounting-services" => "移民相关会计服务",
        "audit-services" => "审计服务",
        "our-team" => "我们的团队",
        "careers" => "职业机会",
        "contact-us" => "联系我们"
      }
    }

    nav_labels.fetch(locale.to_s, nav_labels.fetch("en")).fetch(slug, page.respond_to?(:translation_for) ? page.translation_for(locale)&.title : slug.titleize)
  end

  def header_nav_items
    [
      { slug: "home" },
      { slug: "about-us" },
      { slug: "our-services", children: service_nav_items },
      { slug: "our-team" },
      { slug: "contact-us" }
    ]
  end

  def service_nav_items
    [
      { slug: "our-services/tax-services" },
      { slug: "our-services/business-services" },
      { slug: "our-services/management-consulting" },
      { slug: "our-services/immigration-related-accounting-services" }
    ]
  end

  def footer_link_groups
    labels = {
      "en" => {
        company: "Company",
        services: "Services",
        resources: "Resources",
        immigration_footer: "Immigration-Related Accounting",
        faqs: "FAQs"
      },
      "zh" => {
        company: "公司",
        services: "服务",
        resources: "资源",
        immigration_footer: "移民相关会计",
        faqs: "常见问题"
      }
    }.fetch(current_locale, {})

    [
      {
        title: labels.fetch(:company),
        links: [
          { slug: "about-us" },
          { slug: "our-team" },
          { slug: "careers" }
        ]
      },
      {
        title: labels.fetch(:services),
        links: [
          { slug: "our-services/tax-services" },
          { slug: "our-services/business-services" },
          { slug: "our-services/management-consulting" },
          { slug: "audit-services" },
          { slug: "our-services/immigration-related-accounting-services", label: labels.fetch(:immigration_footer) }
        ]
      },
      {
        title: labels.fetch(:resources),
        links: [
          { label: labels.fetch(:faqs) },
          { slug: "contact-us" }
        ]
      }
    ]
  end

  def nav_item_active?(item)
    slug = item.fetch(:slug)
    children = Array(item[:children])
    @page&.slug == slug || children.any? { |child| @page&.slug == child.fetch(:slug) }
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

  def cms_inline_editing?
    @cms_inline_editing == true
  end

  def cms_previewing?
    @cms_preview == true
  end

  def cms_public_shell?
    @cms_public_shell == true
  end

  def admin_page?
    controller_path.start_with?("admin/")
  end

  def body_classes
    classes = [ "site-body" ]
    classes << page_template_class if !admin_page? || cms_public_shell?
    classes << "cms-inline-body" if cms_inline_editing?
    classes << "cms-preview-body" if cms_previewing?
    classes.compact.join(" ")
  end

  def cms_edit_field(path, value, label:, multiline: false, rows: 2)
    return value unless cms_inline_editing?

    field_id = "cms_field_#{path.to_s.parameterize(separator: "_")}"
    control = if multiline
      text_area_tag("fields[#{path}]", value.to_s, id: field_id, rows: rows, class: "cms-editable__control cms-editable__control--textarea")
    else
      text_field_tag("fields[#{path}]", value.to_s, id: field_id, class: "cms-editable__control")
    end

    content_tag(
      :span,
      safe_join([
        label_tag(field_id, label, class: "cms-editable__label"),
        control
      ]),
      class: "cms-editable"
    )
  end

  def cms_edit_image_picker(path, current_key, label:)
    return nil unless cms_inline_editing?

    assets = @cms_assets || CmsAsset.with_attached_file.order(:key)
    current_asset = assets.detect { |asset| asset.key == current_key.to_s } || CmsAsset.find_by(key: current_key)
    options = assets.map { |asset| [ asset.key, asset.key ] }
    options.unshift([ current_key, current_key ]) if current_key.present? && options.none? { |_, key| key == current_key }

    path_key = path.to_s.parameterize(separator: "_")
    select_id = "cms_image_#{path_key}_selected"
    file_id = "cms_image_#{path_key}_file"
    key_id = "cms_image_#{path_key}_key"
    alt_en_id = "cms_image_#{path_key}_alt_en"
    alt_zh_id = "cms_image_#{path_key}_alt_zh"

    content_tag(:div, class: "cms-image-picker") do
      safe_join([
        content_tag(:strong, label),
        content_tag(:span, "Current key: #{current_key}", class: "cms-image-picker__current"),
        content_tag(:div, class: "cms-image-picker__grid") do
          safe_join([
            content_tag(:label, safe_join([
              content_tag(:span, "Choose existing asset"),
              select_tag("image_fields[#{path}][selected_key]", options_for_select(options, current_key), id: select_id)
            ])),
            content_tag(:label, safe_join([
              content_tag(:span, "Upload replacement"),
              file_field_tag("image_fields[#{path}][file]", id: file_id, accept: CmsAsset::SUPPORTED_CONTENT_TYPES.join(","))
            ])),
            content_tag(:label, safe_join([
              content_tag(:span, "New asset key"),
              text_field_tag("image_fields[#{path}][new_key]", nil, id: key_id, placeholder: "Optional, generated if blank")
            ])),
            content_tag(:label, safe_join([
              content_tag(:span, "Alt text EN"),
              text_field_tag("image_fields[#{path}][alt_text_en]", current_asset&.alt_text_en, id: alt_en_id)
            ])),
            content_tag(:label, safe_join([
              content_tag(:span, "Alt text ZH"),
              text_field_tag("image_fields[#{path}][alt_text_zh]", current_asset&.alt_text_zh, id: alt_zh_id)
            ]))
          ])
        end
      ])
    end
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
      "audit-services" => "office-documents",
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
      "our-services/immigration-related-accounting-services" => "client-meeting",
      "audit-services" => "office-documents"
    }.fetch(slug, "business-advisory")
  end

  def service_asset_fallback(key)
    "tdk/#{key.tr('_', '-')}.jpg"
  end

  def google_maps_embed_url
    "https://www.google.com/maps?q=#{google_maps_business_query}&output=embed"
  end

  def google_maps_open_url
    "https://www.google.com/maps/search/?api=1&query=#{google_maps_business_query}"
  end

  def google_maps_business_query
    ERB::Util.url_encode("TDK Group 1/550 Whitehorse Rd Surrey Hills VIC 3127 Australia")
  end
end
