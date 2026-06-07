class BasReportSnapshot < ApplicationRecord
  STATUS_VALUES = %w[draft final].freeze
  IMMUTABLE_ALLOWED_CHANGES = %w[locked_at locked_by updated_at].freeze

  belongs_to :bas_job, inverse_of: :report_snapshots

  before_validation :normalize_json_attributes
  before_destroy :prevent_destroy_when_final_or_locked

  validates :status, inclusion: { in: STATUS_VALUES }
  validates :totals, presence: true
  validate :totals_are_json_object
  validate :validation_errors_are_array
  validate :final_snapshot_has_approval
  validate :final_snapshot_is_immutable

  scope :recent, -> { order(generated_at: :desc, created_at: :desc, id: :desc) }
  scope :draft, -> { where(status: "draft") }
  scope :final, -> { where(status: "final") }

  def final?
    status == "final"
  end

  def locked?
    locked_at.present?
  end

  private

  def normalize_json_attributes
    self.totals = {} unless totals.is_a?(Hash)
    self.validation_errors = [] unless validation_errors.is_a?(Array)
  end

  def totals_are_json_object
    errors.add(:totals, "must be a JSON object") unless totals.is_a?(Hash)
  end

  def validation_errors_are_array
    errors.add(:validation_errors, "must be a JSON array") unless validation_errors.is_a?(Array)
  end

  def final_snapshot_has_approval
    return unless final?

    errors.add(:approved_at, "must be present for final snapshots") if approved_at.blank?
    errors.add(:approved_by, "must be present for final snapshots") if approved_by.blank?
  end

  def final_snapshot_is_immutable
    return unless persisted?
    return unless status_in_database == "final"

    blocked_changes = changes_to_save.keys - IMMUTABLE_ALLOWED_CHANGES
    errors.add(:base, "Final report snapshots cannot be changed") if blocked_changes.any?
  end

  def prevent_destroy_when_final_or_locked
    return unless final? || locked?

    errors.add(:base, "Final or locked report snapshots cannot be deleted")
    throw :abort
  end
end
