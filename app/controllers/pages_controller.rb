class PagesController < ApplicationController
  before_action :ensure_cms_seeded
  before_action :redirect_root_by_language_preference, only: :show
  before_action :set_page, only: :show
  before_action :set_contact_form, only: :show

  def show
    @translation = @page.translation_for(I18n.locale)
    raise ActiveRecord::RecordNotFound if @translation.blank?

    @content = @translation.content
  end

  private

  def ensure_cms_seeded
    CmsPage.ensure_seeded!
  end

  def redirect_root_by_language_preference
    return unless root_home_request?
    return if cookies.signed[:tdk_locale].present?
    return unless browser_prefers_chinese?

    redirect_to zh_root_path
  end

  def root_home_request?
    params[:slug].to_s == "home" && params[:locale].blank? && request.path == "/"
  end

  def browser_prefers_chinese?
    header = request.headers["HTTP_ACCEPT_LANGUAGE"].to_s.downcase
    return false if header.blank?

    zh_index = header.index("zh")
    en_index = header.index("en")
    zh_index.present? && (en_index.blank? || zh_index < en_index)
  end

  def set_page
    @page = CmsPage.includes(:translations).find_by!(slug: params.fetch(:slug, "home"))
  end

  def set_contact_form
    @contact_form = ContactMessageForm.new if params[:slug].to_s == "contact-us"
  end
end
