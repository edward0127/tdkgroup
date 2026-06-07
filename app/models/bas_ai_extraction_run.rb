class BasAiExtractionRun < ApplicationRecord
  STATUS_VALUES = %w[pending running completed failed needs_review].freeze
  INPUT_KIND_VALUES = %w[document_text job_review matching_review gst_review].freeze
  RAW_CONTENT_KEYS = %w[
    raw_prompt
    prompt
    document_text
    raw_document_text
    raw_response
    full_response
    bank_rows
    invoice_contents
    api_key
  ].freeze

  belongs_to :bas_job, inverse_of: :ai_extraction_runs
  belongs_to :bas_document, optional: true
  has_many :ai_suggestions,
    class_name: "BasAiSuggestion",
    dependent: :destroy,
    inverse_of: :bas_ai_extraction_run

  before_validation :normalize_metadata

  validates :status, inclusion: { in: STATUS_VALUES }
  validates :input_kind, inclusion: { in: INPUT_KIND_VALUES }, allow_blank: true
  validate :document_belongs_to_same_job
  validate :metadata_is_safe

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  private

  def normalize_metadata
    self.metadata = {} unless metadata.is_a?(Hash)
  end

  def document_belongs_to_same_job
    return if bas_job.blank? || bas_document.blank?

    errors.add(:bas_document, "must belong to the same BAS job") if bas_document.bas_job_id != bas_job_id
  end

  def metadata_is_safe
    return unless metadata.is_a?(Hash)

    unsafe_keys = metadata.keys.map(&:to_s) & RAW_CONTENT_KEYS
    errors.add(:metadata, "must not contain raw prompt, document text, responses or secrets") if unsafe_keys.any?
  end
end
