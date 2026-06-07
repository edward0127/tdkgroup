class BasDocumentConversionRun < ApplicationRecord
  CONVERSION_TYPE_VALUES = %w[bank_statement_pdf].freeze
  STATUS_VALUES = %w[pending running previewed imported matched failed abandoned].freeze
  PDF_CONTENT_TYPES = %w[application/pdf].freeze

  belongs_to :bas_job, inverse_of: :document_conversion_runs
  belongs_to :source_bas_document, class_name: "BasDocument", inverse_of: :conversion_runs
  belongs_to :bas_import_run, optional: true, inverse_of: :document_conversion_run

  before_validation :normalize_json_attributes

  validates :conversion_type, inclusion: { in: CONVERSION_TYPE_VALUES }
  validates :status, inclusion: { in: STATUS_VALUES }
  validate :source_document_belongs_to_same_job
  validate :source_document_is_bank_statement
  validate :source_document_is_pdf
  validate :import_run_belongs_to_same_job

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def terminal?
    status.in?(%w[imported matched failed abandoned])
  end

  private

  def normalize_json_attributes
    self.preview_rows = [] unless preview_rows.is_a?(Array)
    self.row_errors = [] unless row_errors.is_a?(Array)
    self.metadata = {} unless metadata.is_a?(Hash)
  end

  def source_document_belongs_to_same_job
    return if bas_job.blank? || source_bas_document.blank?

    errors.add(:source_bas_document, "must belong to the same BAS job") if source_bas_document.bas_job_id != bas_job_id
  end

  def source_document_is_pdf
    return if source_bas_document.blank?
    return if source_bas_document.file.attached? && PDF_CONTENT_TYPES.include?(source_bas_document.file.blob.content_type.to_s)
    return if File.extname(source_bas_document.safe_filename).casecmp(".pdf").zero?

    errors.add(:source_bas_document, "must be a PDF")
  end

  def source_document_is_bank_statement
    return if source_bas_document.blank?
    return if source_bas_document.document_type == "bank_statement"

    errors.add(:source_bas_document, "must be a bank statement")
  end

  def import_run_belongs_to_same_job
    return if bas_job.blank? || bas_import_run.blank?

    errors.add(:bas_import_run, "must belong to the same BAS job") if bas_import_run.bas_job_id != bas_job_id
  end
end
