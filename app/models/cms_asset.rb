class CmsAsset < ApplicationRecord
  MAX_FILE_SIZE = 8.megabytes
  SUPPORTED_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze

  has_one_attached :file

  validates :key, presence: true, uniqueness: true
  validate :file_is_supported_image

  def alt_text(locale)
    locale.to_s == "zh" ? alt_text_zh.presence || alt_text_en : alt_text_en
  end

  private

  def file_is_supported_image
    return unless file.attached?

    unless SUPPORTED_CONTENT_TYPES.include?(file.blob.content_type.to_s)
      errors.add(:file, "must be a JPEG, PNG, WebP or GIF image")
    end

    if file.blob.byte_size > MAX_FILE_SIZE
      errors.add(:file, "must be smaller than 8 MB")
    end
  end
end
