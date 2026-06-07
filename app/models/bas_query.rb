class BasQuery < ApplicationRecord
  QUERY_TYPE_VALUES = %w[
    missing_invoice
    missing_receipt
    unmatched_bank_transaction
    unmatched_invoice
    amount_mismatch
    invoice_direction_unclear
    cash_transaction_direction_unclear
    gst_treatment_unclear
    private_use_unclear
    payroll_unclear
    cash_transaction_unclear
    supporting_document_missing
    import_error
    possible_duplicate
    unreviewed_gst_code
    other
  ].freeze

  STATUS_VALUES = %w[
    open
    waiting_for_client
    resolved
    dismissed
  ].freeze

  CLOSED_STATUS_VALUES = %w[resolved dismissed].freeze

  belongs_to :bas_job, inverse_of: :queries

  before_save :set_resolved_timestamp

  validates :title, presence: true
  validates :query_type, inclusion: { in: QUERY_TYPE_VALUES }
  validates :status, inclusion: { in: STATUS_VALUES }
  validates :dedupe_key, uniqueness: { scope: :bas_job_id, allow_blank: true }
  validate :resolution_notes_are_present_when_closed

  scope :open_items, -> { where(status: %w[open waiting_for_client]) }
  scope :recent, -> { order(updated_at: :desc, id: :desc) }

  def closed?
    CLOSED_STATUS_VALUES.include?(status)
  end

  private

  def resolution_notes_are_present_when_closed
    return unless closed?

    errors.add(:resolution_notes, "must be provided when resolving or dismissing a query") if resolution_notes.blank?
  end

  def set_resolved_timestamp
    if closed?
      self.resolved_at ||= Time.current
    elsif will_save_change_to_status?
      self.resolved_at = nil
    end
  end
end
