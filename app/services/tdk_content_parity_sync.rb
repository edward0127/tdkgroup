class TdkContentParitySync
  PAGE_ATTRIBUTES = %i[template show_in_nav show_in_footer sort_order].freeze
  TRANSLATION_ATTRIBUTES = %i[title seo_title seo_description].freeze

  def initialize(dry_run:, io: $stdout)
    @dry_run = dry_run
    @io = io
    @changes = []
  end

  def call
    CmsPage.transaction do
      TdkOriginalContent.pages.each { |page_data| sync_page(page_data) }
      raise ActiveRecord::Rollback if dry_run
    end

    report
    changes
  end

  private

  attr_reader :dry_run, :io, :changes

  def sync_page(page_data)
    slug = page_data.fetch(:slug)
    page = CmsPage.find_or_initialize_by(slug: slug)
    page_attrs = page_data.slice(*PAGE_ATTRIBUTES)
    record_change(slug, "page", page.new_record? ? "create" : changed_keys(page, page_attrs))

    unless dry_run
      page.assign_attributes(page_attrs)
      page.save!
    end

    CmsPage::LOCALES.each do |locale|
      translation_data = page_data.fetch(locale.to_sym)
      sync_translation(page, slug, locale, translation_data)
    end
  end

  def sync_translation(page, slug, locale, translation_data)
    translation = page.translations.find { |candidate| candidate.locale == locale } ||
      page.translations.find_or_initialize_by(locale: locale)
    payload = json_payload(translation_data.fetch(:content))
    attrs = translation_data.slice(*TRANSLATION_ATTRIBUTES).merge(
      draft_json: payload,
      published_json: payload
    )

    action = translation.new_record? ? "create" : changed_keys(translation, attrs)
    record_change(slug, "translation:#{locale}", action)

    return if dry_run
    return if !translation.new_record? && action.empty? && translation.published_at.present?

    translation.assign_attributes(attrs)
    translation.published_at = Time.current
    translation.save!
  end

  def changed_keys(record, attrs)
    attrs.each_with_object([]) do |(key, value), keys|
      keys << key if normalize_for_compare(record.public_send(key)) != normalize_for_compare(value)
    end
  end

  def record_change(slug, target, action)
    return if action.respond_to?(:empty?) && action.empty?

    changes << { slug: slug, target: target, action: action }
  end

  def report
    return if io.blank?

    io.puts(dry_run ? "TDK content parity dry run. No database changes were written." : "TDK content parity applied.")

    if changes.empty?
      io.puts("No known TDK content parity changes required.")
      return
    end

    changes.each do |change|
      action = change.fetch(:action)
      detail = action.is_a?(Array) ? action.join(", ") : action
      verb = dry_run ? "would update" : "updated"
      verb = dry_run ? "would create" : "created" if detail == "create"
      io.puts("#{verb}: #{change.fetch(:slug)} #{change.fetch(:target)} #{detail}")
    end
  end

  def json_payload(value)
    JSON.parse(JSON.generate(value))
  end

  def normalize_for_compare(value)
    value.is_a?(Hash) || value.is_a?(Array) ? json_payload(value) : value
  end
end
