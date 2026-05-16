class CmsAssetVersion < ApplicationRecord
  belongs_to :cms_asset, inverse_of: :versions

  has_one_attached :file

  validate :file_is_attached
  validate :file_is_supported_image

  def alt_text(locale)
    locale.to_s == "zh" ? alt_text_zh.presence || alt_text_en : alt_text_en
  end

  private

  def file_is_attached
    errors.add(:file, "must be attached") unless file.attached?
  end

  def file_is_supported_image
    return unless file.attached?

    unless CmsAsset::SUPPORTED_CONTENT_TYPES.include?(file.blob.content_type.to_s)
      errors.add(:file, "must be a JPEG, PNG, WebP or GIF image")
    end

    if file.blob.byte_size > CmsAsset::MAX_FILE_SIZE
      errors.add(:file, "must be smaller than 8 MB")
    end
  end
end
