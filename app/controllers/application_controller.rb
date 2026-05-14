class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_locale

  helper_method :current_locale, :localized_slug_path, :tdk_t, :admin_signed_in?

  private

  def set_locale
    I18n.locale = params[:locale].presence_in(CmsPage::LOCALES) ||
      cookies.signed[:tdk_locale].presence_in(CmsPage::LOCALES) ||
      browser_locale ||
      I18n.default_locale
  end

  def browser_locale
    header = request.headers["HTTP_ACCEPT_LANGUAGE"].to_s.downcase
    return "zh" if header.include?("zh") && !header.start_with?("en")

    nil
  end

  def current_locale
    I18n.locale.to_s
  end

  def localized_slug_path(slug, locale: current_locale)
    normalized = slug.to_s.presence || "home"

    if locale.to_s == "zh"
      normalized == "home" ? zh_root_path : "/zh/#{normalized}"
    else
      normalized == "home" ? root_path : "/#{normalized}"
    end
  end

  def tdk_t(key)
    I18n.t(key, locale: current_locale)
  end

  def admin_signed_in?
    session[:admin_authenticated] == true
  end
end
