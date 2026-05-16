class CmsAsset < ApplicationRecord
  MAX_FILE_SIZE = 8.megabytes
  SUPPORTED_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze

  has_many :versions,
    -> { order(created_at: :desc, id: :desc) },
    class_name: "CmsAssetVersion",
    dependent: :destroy,
    inverse_of: :cms_asset
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

  def replace_file(replacement_file:, alt_text_en:, alt_text_zh:, admin_identifier: nil)
    replacement_present = replacement_file.present?

    with_lock do
      previous_blob = file.blob if replacement_present && file.attached?
      previous_alt_text_en = self.alt_text_en
      previous_alt_text_zh = self.alt_text_zh

      assign_attributes(alt_text_en: alt_text_en, alt_text_zh: alt_text_zh)
      self.file = replacement_file if replacement_present

      if valid?
        transaction do
          snapshot_file!(
            blob: previous_blob,
            alt_text_en: previous_alt_text_en,
            alt_text_zh: previous_alt_text_zh,
            admin_identifier: admin_identifier
          ) if replacement_present && previous_blob.present?

          save!
        end
        true
      else
        false
      end
    end
  end

  def restore_version(version, restore_alt_text:, admin_identifier: nil)
    raise ArgumentError, "Version does not belong to asset" unless version.cms_asset_id == id

    with_lock do
      current_blob = file.blob if file.attached?
      current_alt_text_en = alt_text_en
      current_alt_text_zh = alt_text_zh

      self.file = version.file.blob
      if restore_alt_text
        self.alt_text_en = version.alt_text_en
        self.alt_text_zh = version.alt_text_zh
      end

      if valid?
        transaction do
          snapshot_file!(
            blob: current_blob,
            alt_text_en: current_alt_text_en,
            alt_text_zh: current_alt_text_zh,
            admin_identifier: admin_identifier
          ) if current_blob.present?

          save!
        end
        true
      else
        false
      end
    end
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

  def snapshot_file!(blob:, alt_text_en:, alt_text_zh:, admin_identifier:)
    version = versions.build(
      alt_text_en: alt_text_en,
      alt_text_zh: alt_text_zh,
      admin_identifier: admin_identifier
    )
    version.file.attach(blob)
    version.save!
  end

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
