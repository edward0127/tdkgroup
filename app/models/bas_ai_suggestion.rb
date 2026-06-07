class BasAiSuggestion < ApplicationRecord
  SUGGESTION_TYPE_VALUES = %w[
    invoice_extraction
    gst_code
    match
    query
    summary
  ].freeze

  STATUS_VALUES = %w[proposed accepted rejected needs_review].freeze
  REVIEW_STATUS_VALUES = %w[accepted rejected needs_review].freeze

  belongs_to :bas_job, inverse_of: :ai_suggestions
  belongs_to :bas_ai_extraction_run, inverse_of: :ai_suggestions

  before_validation :normalize_suggested_data

  validates :suggestion_type, inclusion: { in: SUGGESTION_TYPE_VALUES }
  validates :status, inclusion: { in: STATUS_VALUES }
  validates :confidence,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100, allow_nil: true }
  validate :suggested_data_is_object
  validate :run_belongs_to_same_job
  validate :locked_job_does_not_allow_review_changes

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :proposed, -> { where(status: "proposed") }

  def accepted?
    status == "accepted"
  end

  def rejected?
    status == "rejected"
  end

  private

  def normalize_suggested_data
    self.suggested_data = {} unless suggested_data.is_a?(Hash)
  end

  def suggested_data_is_object
    errors.add(:suggested_data, "must be a JSON object") unless suggested_data.is_a?(Hash)
  end

  def run_belongs_to_same_job
    return if bas_job.blank? || bas_ai_extraction_run.blank?

    if bas_ai_extraction_run.bas_job_id != bas_job_id
      errors.add(:bas_ai_extraction_run, "must belong to the same BAS job")
    end
  end

  def locked_job_does_not_allow_review_changes
    return unless persisted?
    return unless bas_job&.locked?
    return unless will_save_change_to_status?
    return unless REVIEW_STATUS_VALUES.include?(status)

    errors.add(:base, "Locked BAS jobs cannot have AI suggestions applied or reviewed")
  end
end
