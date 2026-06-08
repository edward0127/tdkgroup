class BasClient < ApplicationRecord
  CLEANUP_DELETE_BLOCKED_MESSAGE = "This client has BAS jobs. Delete draft/test jobs first, then delete the client."

  GST_BASIS_VALUES = %w[unknown cash accrual].freeze
  REPORTING_FREQUENCY_VALUES = %w[monthly quarterly annually unknown].freeze
  REPORTING_METHOD_VALUES = %w[unknown simpler_bas full_bas].freeze

  has_many :bas_jobs, dependent: :restrict_with_error

  before_destroy :prevent_destroy_with_jobs, prepend: true

  validates :legal_name, presence: true
  validates :default_gst_basis, inclusion: { in: GST_BASIS_VALUES }
  validates :reporting_frequency, inclusion: { in: REPORTING_FREQUENCY_VALUES }
  validates :default_reporting_method, inclusion: { in: REPORTING_METHOD_VALUES }
  validates :contact_email,
    format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }

  scope :active, -> { where(archived: false) }
  scope :ordered, -> { order(archived: :asc, legal_name: :asc, id: :asc) }

  def display_name
    legal = legal_name.to_s.squish
    trading = trading_name.to_s.squish
    name = legal.presence || trading.presence || "Unnamed BAS client"

    if legal.present? && trading.present? && !trading.casecmp?(legal)
      name = "#{name} (#{trading})"
    end

    abn_label = formatted_abn
    return name if abn_label.blank?

    "#{name}  ABN #{abn_label}"
  end

  def cleanup_deletable?
    !bas_jobs.exists?
  end

  private

  def formatted_abn
    raw_abn = abn.to_s.squish
    digits = raw_abn.gsub(/\D/, "")

    return raw_abn if raw_abn.blank? || digits.length != 11

    "#{digits[0, 2]} #{digits[2, 3]} #{digits[5, 3]} #{digits[8, 3]}"
  end

  def prevent_destroy_with_jobs
    return if cleanup_deletable?

    errors.add(:base, CLEANUP_DELETE_BLOCKED_MESSAGE)
    throw :abort
  end
end
