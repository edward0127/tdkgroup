module Admin
  class CmsPagesController < BaseController
    before_action :set_page, only: [ :edit, :update, :publish ]

    def index
      @pages = CmsPage.includes(:translations).ordered
    end

    def edit
      @translations = translations_by_locale
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
      redirect_to edit_admin_cms_page_path(@page), notice: "Published content updated."
    end

    private

    def set_page
      @page = CmsPage.includes(:translations).find_by!(slug: params[:id])
    end

    def page_params
      params.require(:cms_page).permit(:template, :show_in_nav, :show_in_footer, :sort_order)
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
