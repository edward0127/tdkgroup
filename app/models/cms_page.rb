class CmsPage < ApplicationRecord
  LOCALES = %w[en zh].freeze

  has_many :translations, class_name: "CmsPageTranslation", dependent: :destroy, inverse_of: :cms_page

  validates :slug, presence: true, uniqueness: true
  validates :template, presence: true
  validates :sort_order, numericality: { only_integer: true }

  scope :ordered, -> { order(:sort_order, :id) }
  scope :visible_in_nav, -> { where(show_in_nav: true).ordered }
  scope :visible_in_footer, -> { where(show_in_footer: true).ordered }

  def translation_for(locale)
    translations.detect { |translation| translation.locale == locale.to_s } ||
      translations.find_by(locale: locale.to_s) ||
      translations.find_by(locale: "en")
  end

  def to_param
    slug
  end

  def self.ensure_seeded!
    return if exists? && CmsSeeder.required_assets_attached?

    CmsSeeder.seed!
  end
end
