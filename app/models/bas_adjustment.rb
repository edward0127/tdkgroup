class BasAdjustment < ApplicationRecord
  ADJUSTMENT_TYPE_VALUES = %w[
    gst_on_sales
    gst_on_purchases
    total_sales
    payroll_gross_wages
    payg_withheld
    other
  ].freeze

  belongs_to :bas_job, inverse_of: :adjustments

  validates :adjustment_type, inclusion: { in: ADJUSTMENT_TYPE_VALUES }
  validates :label, :amount, :reason, presence: true
  validate :job_is_not_locked

  before_destroy :prevent_destroy_when_job_locked

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  private

  def job_is_not_locked
    return if bas_job.blank? || !bas_job.locked?

    errors.add(:base, "Locked BAS jobs cannot have adjustments changed")
  end

  def prevent_destroy_when_job_locked
    return unless bas_job&.locked?

    errors.add(:base, "Locked BAS jobs cannot have adjustments changed")
    throw :abort
  end
end
