class BasInvoice < ApplicationRecord
  DIRECTION_VALUES = %w[sale purchase unknown].freeze
  PAYMENT_METHOD_VALUES = %w[bank cash mixed unpaid unknown].freeze
  GST_CODE_VALUES = %w[
    taxable
    gst_free
    input_taxed
    no_gst
    bas_excluded
    needs_review
    unknown
  ].freeze
  STATUS_VALUES = %w[imported matched ignored needs_review].freeze

  belongs_to :bas_job
  belongs_to :bas_import_run, optional: true, inverse_of: :invoices
  has_many :match_items, as: :matchable, class_name: "BasMatchItem", dependent: :destroy
  has_many :matches, through: :match_items, source: :bas_match

  validates :direction, inclusion: { in: DIRECTION_VALUES }
  validates :payment_method, inclusion: { in: PAYMENT_METHOD_VALUES }
  validates :gst_code, inclusion: { in: GST_CODE_VALUES }
  validates :status, inclusion: { in: STATUS_VALUES }
  validate :import_run_belongs_to_same_job

  scope :recent, -> { order(issue_date: :desc, id: :desc) }
  scope :matchable, -> { where(status: %w[imported needs_review]) }
  scope :unmatched, -> {
    accepted_match_ids = BasMatchItem
      .joins(:bas_match)
      .where(matchable_type: "BasInvoice", bas_matches: { status: "accepted" })
      .select(:matchable_id)

    where.not(status: %w[matched ignored]).where.not(gst_code: "bas_excluded").where.not(id: accepted_match_ids)
  }

  private

  def import_run_belongs_to_same_job
    return if bas_job.blank? || bas_import_run.blank?

    errors.add(:bas_import_run, "must belong to the same BAS job") if bas_import_run.bas_job_id != bas_job_id
  end
end
