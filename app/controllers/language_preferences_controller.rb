class LanguagePreferencesController < ApplicationController
  def create
    locale = params[:locale].to_s
    locale = "en" unless CmsPage::LOCALES.include?(locale)
    cookies.signed.permanent[:tdk_locale] = locale

    redirect_to localized_slug_path(params[:slug].presence || "home", locale: locale)
  end
end
