class CmsPageTranslation < ApplicationRecord
  belongs_to :cms_page, inverse_of: :translations

  validates :locale, inclusion: { in: CmsPage::LOCALES }
  validates :title, presence: true
  validates :cms_page_id, uniqueness: { scope: :locale }
  validate :json_payloads_are_hashes

  before_validation :normalize_payloads

  def content
    published_json.presence || draft_json.presence || {}
  end

  def draft_content
    draft_json.presence || published_json.presence || {}
  end

  def publish!
    update!(published_json: draft_json.presence || published_json, published_at: Time.current)
  end

  private

  def normalize_payloads
    self.published_json = {} unless published_json.is_a?(Hash)
    self.draft_json = published_json if draft_json.blank?
  end

  def json_payloads_are_hashes
    errors.add(:published_json, "must be an object") unless published_json.is_a?(Hash)
    errors.add(:draft_json, "must be an object") unless draft_json.is_a?(Hash)
  end
end
