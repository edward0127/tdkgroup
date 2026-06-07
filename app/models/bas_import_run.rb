class BasImportRun < ApplicationRecord
  IMPORT_TYPE_VALUES = %w[
    bank_statement
    invoice_summary
    cash_transactions
    payroll_summary
  ].freeze

  STATUS_VALUES = %w[
    pending
    previewed
    imported
    failed
    reverted
  ].freeze

  belongs_to :bas_job
  belongs_to :bas_document
  has_one :document_conversion_run,
    class_name: "BasDocumentConversionRun",
    dependent: :nullify,
    inverse_of: :bas_import_run
  has_many :bank_transactions,
    class_name: "BasBankTransaction",
    dependent: :restrict_with_error,
    inverse_of: :bas_import_run
  has_many :invoices,
    class_name: "BasInvoice",
    dependent: :restrict_with_error,
    inverse_of: :bas_import_run
  has_many :cash_transactions,
    class_name: "BasCashTransaction",
    dependent: :restrict_with_error,
    inverse_of: :bas_import_run
  has_many :payroll_summaries,
    class_name: "BasPayrollSummary",
    dependent: :restrict_with_error,
    inverse_of: :bas_import_run

  before_validation :normalize_json_attributes

  validates :import_type, inclusion: { in: IMPORT_TYPE_VALUES }
  validates :status, inclusion: { in: STATUS_VALUES }
  validate :document_belongs_to_same_job

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def import_errors
    row_errors.is_a?(Array) ? row_errors : []
  end

  def import_errors=(value)
    self.row_errors = value.is_a?(Array) ? value : []
  end

  def imported_record_count
    bank_transactions.size + invoices.size + cash_transactions.size + payroll_summaries.size
  end

  private

  def normalize_json_attributes
    self.column_mapping = {} unless column_mapping.is_a?(Hash)
    self.preview_rows = [] unless preview_rows.is_a?(Array)
    self.row_errors = [] unless row_errors.is_a?(Array)
  end

  def document_belongs_to_same_job
    return if bas_job.blank? || bas_document.blank?

    errors.add(:bas_document, "must belong to the same BAS job") if bas_document.bas_job_id != bas_job_id
  end
end
