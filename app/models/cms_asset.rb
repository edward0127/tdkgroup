class CmsAsset < ApplicationRecord
  MAX_FILE_SIZE = 8.megabytes
  SUPPORTED_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze

  has_one_attached :file

  validates :key, presence: true, uniqueness: true
  validate :file_is_supported_image

  def self.in_use_keys
    keys = {}
    required_asset_keys.each { |asset_key| keys[asset_key] = true }

    CmsPageTranslation.find_each do |translation|
      collect_string_values(translation.draft_json, keys)
      collect_string_values(translation.published_json, keys)
    end

    keys.keys
  end

  def self.required_asset_keys
    CmsSeeder::ASSETS.map { |asset_data| asset_data.fetch(:key) }
  end

  def alt_text(locale)
    locale.to_s == "zh" ? alt_text_zh.presence || alt_text_en : alt_text_en
  end

  def in_use?
    self.class.in_use_keys.include?(key)
  end

  private

  def self.collect_string_values(value, keys)
    case value
    when Hash
      value.each_value { |nested_value| collect_string_values(nested_value, keys) }
    when Array
      value.each { |nested_value| collect_string_values(nested_value, keys) }
    when String
      keys[value] = true
    end
  end

  private_class_method :collect_string_values

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
