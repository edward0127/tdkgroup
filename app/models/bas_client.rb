class BasClient < ApplicationRecord
  GST_BASIS_VALUES = %w[unknown cash accrual].freeze
  REPORTING_FREQUENCY_VALUES = %w[monthly quarterly annually unknown].freeze
  REPORTING_METHOD_VALUES = %w[unknown simpler_bas full_bas].freeze

  has_many :bas_jobs, dependent: :restrict_with_error

  validates :legal_name, presence: true
  validates :default_gst_basis, inclusion: { in: GST_BASIS_VALUES }
  validates :reporting_frequency, inclusion: { in: REPORTING_FREQUENCY_VALUES }
  validates :default_reporting_method, inclusion: { in: REPORTING_METHOD_VALUES }
  validates :contact_email,
    format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }

  scope :active, -> { where(archived: false) }
  scope :ordered, -> { order(archived: :asc, legal_name: :asc, id: :asc) }

  def display_name
    trading_name.presence || legal_name
  end
end
