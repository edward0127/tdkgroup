require "cgi"

class SitemapsController < ApplicationController
  before_action :ensure_cms_seeded

  def show
    @pages = CmsPage.includes(:translations).ordered

    render plain: sitemap_xml, content_type: "application/xml; charset=utf-8"
  end

  private

  def ensure_cms_seeded
    CmsPage.ensure_seeded!
  end

  def sitemap_xml
    entries = @pages.flat_map do |page|
      CmsPage::LOCALES.map do |locale|
        {
          loc: "#{request.base_url}#{localized_slug_path(page.slug, locale: locale)}",
          lastmod: page.translations.map(&:updated_at).compact.max&.to_date&.iso8601
        }
      end
    end

    lines = [
      %(<?xml version="1.0" encoding="UTF-8"?>),
      %(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">)
    ]

    entries.each do |entry|
      lines << "  <url>"
      lines << "    <loc>#{xml_escape(entry.fetch(:loc))}</loc>"
      lines << "    <lastmod>#{entry.fetch(:lastmod)}</lastmod>" if entry[:lastmod].present?
      lines << "  </url>"
    end

    lines << "</urlset>"
    lines.join("\n")
  end

  def xml_escape(value)
    CGI.escapeHTML(value.to_s)
  end
end
