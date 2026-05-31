require "stringio"

class CmsSeeder
  ASSETS = [
    { key: "tdk-logo", file: "tdk-logo.jpg", content_type: "image/jpeg", alt_en: "TDK Group Pty Ltd logo", alt_zh: "黄金会计师事务所标志" },
    { key: "hero-handshake", file: "hero-handshake.jpg", content_type: "image/jpeg", alt_en: "Professional business handshake", alt_zh: "专业商务握手" },
    { key: "business-advisory", file: "business-advisory.jpg", content_type: "image/jpeg", alt_en: "Business advisory meeting", alt_zh: "商业咨询会议" },
    { key: "client-meeting", file: "client-meeting.jpg", content_type: "image/jpeg", alt_en: "International business and migration accounting support", alt_zh: "国际业务与移民相关会计支持" },
    { key: "office-documents", file: "office-documents.jpg", content_type: "image/jpeg", alt_en: "Financial reports and business documents", alt_zh: "财务报表与商业文件" },
    { key: "tax-service", file: "tax-service.jpg", content_type: "image/jpeg", alt_en: "Tax planning and accounting strategy", alt_zh: "税务规划与会计策略" },
    { key: "consulting-service", file: "consulting-service.jpg", content_type: "image/jpeg", alt_en: "Consulting meeting with financial charts", alt_zh: "财务图表咨询会议" },
    { key: "business-service", file: "business-service.jpg", content_type: "image/jpeg", alt_en: "Calculator and business accounting documents", alt_zh: "计算器与商业会计文件" },
    { key: "cpa-practice", file: "cpa-practice.png", content_type: "image/png", alt_en: "TDK professional practice banner", alt_zh: "TDK 专业资质横幅" },
    { key: "cpa-liability", file: "cpa-liability.png", content_type: "image/png", alt_en: "CPA Australia and professional standards credentials", alt_zh: "CPA Australia 与专业责任资质" }
  ].freeze

  def self.seed!
    new.seed!
  end

  def self.required_assets_attached?
    seeder = new
    ASSETS.all? do |asset_data|
      asset = CmsAsset.find_by(key: asset_data.fetch(:key))
      seeder.send(:asset_available?, asset)
    end
  end

  def seed!
    TdkOriginalContent.pages.each { |page| upsert_page(page) }
    seed_assets!
  end

  private

  def seed_assets!
    ASSETS.each do |asset_data|
      asset = CmsAsset.find_or_initialize_by(key: asset_data.fetch(:key))
      asset.assign_attributes(
        alt_text_en: asset.alt_text_en.presence || asset_data.fetch(:alt_en),
        alt_text_zh: asset.alt_text_zh.presence || asset_data.fetch(:alt_zh)
      )

      asset_path = Rails.root.join("app/assets/images/tdk", asset_data.fetch(:file))
      if asset_path.exist? && !asset_available?(asset)
        asset.file.purge if asset.file.attached?
        asset.file.attach(
          io: StringIO.new(asset_path.binread),
          filename: asset_data.fetch(:file),
          content_type: asset_data.fetch(:content_type),
          identify: false
        )
      end

      asset.save!
    end
  end

  def asset_available?(asset)
    return false unless asset&.file&.attached?

    asset.file.blob.service.exist?(asset.file.blob.key)
  rescue ActiveStorage::FileNotFoundError, Errno::ENOENT
    false
  end

  def upsert_page(page)
    cms_page = CmsPage.find_or_initialize_by(slug: page.fetch(:slug))
    cms_page.assign_attributes(page.slice(:template, :show_in_nav, :show_in_footer, :sort_order))
    cms_page.save!

    upsert_translation(cms_page, "en", page.fetch(:en))
    upsert_translation(cms_page, "zh", page.fetch(:zh))
  end

  def upsert_translation(cms_page, locale, data)
    translation = cms_page.translations.find_or_initialize_by(locale: locale)
    payload = JSON.parse(JSON.generate(data.fetch(:content)))
    translation.assign_attributes(
      title: data.fetch(:title),
      seo_title: data[:seo_title],
      seo_description: data[:seo_description],
      published_json: translation.published_json.presence || payload,
      draft_json: translation.draft_json.presence || payload,
      published_at: translation.published_at || Time.current
    )
    translation.save!
  end
end
