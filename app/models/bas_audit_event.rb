class BasAuditEvent < ApplicationRecord
  CLIENT_EVENT_TYPES = %w[bas_client_created bas_client_updated].freeze

  belongs_to :bas_job, optional: true, inverse_of: :audit_events
  belongs_to :auditable, polymorphic: true, optional: true

  before_validation :normalize_metadata

  validates :event_type, presence: true
  validate :audit_scope_is_present

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  private

  def normalize_metadata
    self.metadata = {} unless metadata.is_a?(Hash)
  end

  def audit_scope_is_present
    return if bas_job.present?
    return if CLIENT_EVENT_TYPES.include?(event_type) && auditable.is_a?(BasClient)

    errors.add(:bas_job, "must exist for job-scoped audit events")
  end
end
