module Admin
  class CmsPagesController < BaseController
    before_action :set_page, only: [ :edit, :update, :inline_edit, :inline_update, :preview, :publish ]

    layout :cms_page_layout

    def index
      @pages = CmsPage.includes(:translations).ordered
    end

    def edit
      @translations = translations_by_locale
    end

    def inline_edit
      prepare_inline_editor
    end

    def inline_update
      locale = inline_locale
      translation = @page.translations.find_by!(locale: locale)
      draft_payload = translation.draft_content.deep_dup

      apply_inline_text_fields!(draft_payload, params[:fields])
      apply_inline_image_fields!(draft_payload, params[:image_fields])
      translation.update!(draft_json: draft_payload)

      destination = params[:after_save] == "preview" ?
        preview_admin_cms_page_path(@page, locale: locale) :
        inline_edit_admin_cms_page_path(@page, locale: locale)

      redirect_to destination, notice: "Draft content saved."
    rescue ActiveRecord::RecordInvalid => e
      prepare_inline_editor(locale: locale || inline_locale)
      flash.now[:alert] = "Draft could not be saved: #{e.record.errors.full_messages.to_sentence}"
      render :inline_edit, status: :unprocessable_entity
    end

    def preview
      locale = inline_locale
      @translation = @page.translations.find_by!(locale: locale)
      @content = @translation.draft_content
      @contact_form = ContactMessageForm.new if @page.slug == "contact-us"
      @cms_preview = true
      @cms_public_shell = true
      @preview_locale = locale

      render "pages/show"
    end

    def update
      @page.assign_attributes(page_params)

      CmsPage.transaction do
        @page.save!
        update_translations!
      end

      redirect_to edit_admin_cms_page_path(@page), notice: "Draft content saved."
    rescue JSON::ParserError => e
      @translations = translations_by_locale
      flash.now[:alert] = "Draft JSON is invalid: #{e.message}"
      render :edit, status: :unprocessable_entity
    rescue ActiveRecord::RecordInvalid
      @translations = translations_by_locale
      flash.now[:alert] = "Page could not be saved."
      render :edit, status: :unprocessable_entity
    end

    def publish
      locale = params[:locale].presence
      translations = locale.present? ? [ @page.translations.find_by!(locale: locale) ] : @page.translations
      translations.each(&:publish!)
      redirect_to publish_return_path(locale), notice: "Published content updated."
    end

    private

    def cms_page_layout
      %w[inline_edit inline_update preview].include?(action_name) ? "application" : "admin"
    end

    def set_page
      @page = CmsPage.includes(:translations).find_by!(slug: params[:id])
    end

    def prepare_inline_editor(locale: inline_locale)
      @edit_locale = locale
      @translation = @page.translations.find_by!(locale: locale)
      @content = @translation.draft_content
      @contact_form = ContactMessageForm.new if @page.slug == "contact-us"
      @cms_assets = CmsAsset.with_attached_file.order(:key)
      @cms_inline_editing = true
      @cms_public_shell = true
    end

    def inline_locale
      locale = params[:locale].to_s.presence_in(CmsPage::LOCALES) ||
        I18n.locale.to_s.presence_in(CmsPage::LOCALES) ||
        "en"
      I18n.locale = locale
      locale
    end

    def page_params
      params.require(:cms_page).permit(:template, :show_in_nav, :show_in_footer, :sort_order)
    end

    def apply_inline_text_fields!(draft_payload, submitted_fields)
      allowed_paths = editable_text_paths(draft_payload)
      submitted_fields_hash(submitted_fields).each do |path, value|
        next unless allowed_paths.include?(path.to_s)

        assign_nested_value!(draft_payload, path.to_s, value.to_s)
      end
    end

    def apply_inline_image_fields!(draft_payload, submitted_fields)
      allowed_paths = editable_image_paths(draft_payload)
      submitted_fields_hash(submitted_fields).each do |path, attrs|
        next unless allowed_paths.include?(path.to_s)

        attrs = attrs.to_h
        file = attrs["file"]

        if uploaded_file_present?(file)
          asset = cms_asset_from_upload(path, attrs, file)
          asset.save!
          assign_nested_value!(draft_payload, path.to_s, asset.key)
        elsif attrs["selected_key"].present?
          asset = CmsAsset.find_by(key: attrs["selected_key"])
          next unless asset&.file&.attached?

          asset.assign_attributes(
            alt_text_en: attrs["alt_text_en"],
            alt_text_zh: attrs["alt_text_zh"]
          )
          asset.save! if asset.changed?
          assign_nested_value!(draft_payload, path.to_s, asset.key)
        end
      end
    end

    def cms_asset_from_upload(path, attrs, file)
      key = normalized_asset_key(attrs["new_key"]) ||
        generated_asset_key(path)
      asset = CmsAsset.find_or_initialize_by(key: key)
      asset.alt_text_en = attrs["alt_text_en"]
      asset.alt_text_zh = attrs["alt_text_zh"]
      asset.file.attach(file)
      asset
    end

    def editable_text_paths(content)
      paths = []
      hero = content["hero"]

      if hero.is_a?(Hash)
        %w[eyebrow title lead primary_label secondary_label].each do |key|
          paths << "hero.#{key}" if hero.key?(key)
        end

        Array(hero["stats"]).each_with_index do |stat, index|
          next unless stat.is_a?(Hash)

          %w[value label].each do |key|
            paths << "hero.stats.#{index}.#{key}" if stat.key?(key)
          end
        end
      end

      Array(content["sections"]).each_with_index do |block, section_index|
        next unless block.is_a?(Hash)

        %w[eyebrow title subtitle label contact].each do |key|
          paths << "sections.#{section_index}.#{key}" if block.key?(key)
        end

        if block["body"].is_a?(Array)
          block["body"].each_index { |index| paths << "sections.#{section_index}.body.#{index}" }
        elsif block.key?("body")
          paths << "sections.#{section_index}.body"
        end

        Array(block["bullets"]).each_index do |index|
          paths << "sections.#{section_index}.bullets.#{index}"
        end

        Array(block["items"]).each_with_index do |item, item_index|
          next unless item.is_a?(Hash)

          %w[title body label].each do |key|
            paths << "sections.#{section_index}.items.#{item_index}.#{key}" if item.key?(key)
          end
        end

        Array(block["details"]).each_with_index do |detail, detail_index|
          next unless detail.is_a?(Hash)

          %w[label value].each do |key|
            paths << "sections.#{section_index}.details.#{detail_index}.#{key}" if detail.key?(key)
          end
        end
      end

      paths
    end

    def editable_image_paths(content)
      paths = []
      paths << "hero.image_key" if content["hero"].is_a?(Hash)

      Array(content["sections"]).each_with_index do |block, section_index|
        next unless block.is_a?(Hash)

        case block["kind"].to_s
        when "intro", "profile", "contact"
          paths << "sections.#{section_index}.image_key"
        when "cards"
          Array(block["items"]).each_with_index do |item, item_index|
            paths << "sections.#{section_index}.items.#{item_index}.image_key" if item.is_a?(Hash)
          end
        end
      end

      paths
    end

    def submitted_fields_hash(submitted_fields)
      return {} if submitted_fields.blank?

      submitted_fields.respond_to?(:to_unsafe_h) ? submitted_fields.to_unsafe_h : submitted_fields.to_h
    end

    def assign_nested_value!(payload, path, value)
      keys = path.split(".")
      current = payload

      keys.each_with_index do |key, index|
        last_key = index == keys.length - 1

        if current.is_a?(Array)
          array_index = numeric_key?(key) ? key.to_i : nil
          return if array_index.nil?

          current[array_index] ||= next_container_for(keys[index + 1])
          last_key ? current[array_index] = value : current = current[array_index]
        elsif current.is_a?(Hash)
          current[key] ||= next_container_for(keys[index + 1])
          last_key ? current[key] = value : current = current[key]
        else
          return
        end
      end
    end

    def next_container_for(next_key)
      numeric_key?(next_key.to_s) ? [] : {}
    end

    def numeric_key?(key)
      key.to_s.match?(/\A\d+\z/)
    end

    def uploaded_file_present?(file)
      file.respond_to?(:size) && file.size.to_i.positive?
    end

    def normalized_asset_key(value)
      value.to_s.downcase.gsub(/[^a-z0-9_-]+/, "-").gsub(/\A-+|-+\z/, "").presence
    end

    def generated_asset_key(path)
      page_key = @page.slug.tr("/", "-")
      "cms-#{page_key}-#{inline_locale}-#{path.tr('.', '-')}-#{Time.current.to_i}"
    end

    def publish_return_path(locale)
      case params[:return_to].to_s
      when "inline_edit"
        inline_edit_admin_cms_page_path(@page, locale: locale.presence || inline_locale)
      when "preview"
        preview_admin_cms_page_path(@page, locale: locale.presence || inline_locale)
      else
        edit_admin_cms_page_path(@page)
      end
    end

    def update_translations!
      translation_params.each do |locale, attrs|
        attrs = attrs.with_indifferent_access
        translation = @page.translations.find_or_initialize_by(locale: locale)
        draft_payload = JSON.parse(attrs.fetch(:draft_json).to_s)

        translation.update!(
          title: attrs[:title],
          seo_title: attrs[:seo_title],
          seo_description: attrs[:seo_description],
          draft_json: draft_payload
        )
      end
    end

    def translation_params
      params.require(:translations).permit(
        en: [ :title, :seo_title, :seo_description, :draft_json ],
        zh: [ :title, :seo_title, :seo_description, :draft_json ]
      ).to_h
    end

    def translations_by_locale
      CmsPage::LOCALES.index_with do |locale|
        @page.translations.find { |translation| translation.locale == locale } ||
          @page.translations.build(locale: locale, title: @page.slug.titleize, published_json: {}, draft_json: {})
      end
    end
  end
end
