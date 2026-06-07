class BasMatchItem < ApplicationRecord
  MATCHABLE_TYPES = %w[BasBankTransaction BasInvoice BasCashTransaction].freeze

  belongs_to :bas_match, inverse_of: :items
  belongs_to :matchable, polymorphic: true

  validates :matchable_type, inclusion: { in: MATCHABLE_TYPES }
  validate :matchable_belongs_to_same_job

  private

  def matchable_belongs_to_same_job
    return if bas_match.blank? || matchable.blank?
    return if matchable.respond_to?(:bas_job_id) && matchable.bas_job_id == bas_match.bas_job_id

    errors.add(:matchable, "must belong to the same BAS job")
  end
end
