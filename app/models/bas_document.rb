class BasDocument < ApplicationRecord
  DOCUMENT_TYPE_VALUES = %w[
    bank_statement
    invoice_summary
    sales_invoice
    supplier_invoice
    receipt
    cash_transaction_list
    payroll_summary
    ato_bas_form
    other
  ].freeze

  PROCESSING_STATUS_VALUES = %w[
    not_processed
    queued
    processed
    failed
    needs_review
  ].freeze

  MAX_FILE_SIZE = 25.megabytes
  SUPPORTED_CONTENT_TYPES = %w[
    text/csv
    application/csv
    application/pdf
    application/vnd.ms-excel
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    image/jpeg
    image/png
    image/webp
  ].freeze
  SAFE_OCTET_STREAM_EXTENSIONS = %w[csv xls xlsx pdf jpg jpeg png webp].freeze
  ACCEPT_ATTRIBUTE = (SUPPORTED_CONTENT_TYPES + SAFE_OCTET_STREAM_EXTENSIONS.map { |extension| ".#{extension}" }).join(",")

  belongs_to :bas_job, inverse_of: :documents
  has_many :import_runs,
    class_name: "BasImportRun",
    dependent: :restrict_with_error,
    inverse_of: :bas_document
  has_many :conversion_runs,
    class_name: "BasDocumentConversionRun",
    foreign_key: :source_bas_document_id,
    dependent: :restrict_with_error,
    inverse_of: :source_bas_document
  has_one_attached :file, dependent: :purge_later

  before_validation :copy_source_filename_from_file
  before_validation :normalize_metadata

  validates :title, presence: true
  validates :document_type, inclusion: { in: DOCUMENT_TYPE_VALUES }
  validates :processing_status, inclusion: { in: PROCESSING_STATUS_VALUES }
  validate :file_is_attached
  validate :file_is_supported_financial_document

  scope :ordered, -> { order(:document_type, created_at: :desc, id: :desc) }

  def safe_filename
    source_filename.presence || file.filename.to_s
  end

  private

  def copy_source_filename_from_file
    self.source_filename = file.filename.to_s if source_filename.blank? && file.attached?
  end

  def normalize_metadata
    self.metadata = {} unless metadata.is_a?(Hash)
  end

  def file_is_attached
    errors.add(:file, "must be attached") unless file.attached?
  end

  def file_is_supported_financial_document
    return unless file.attached?

    if file.blob.byte_size > MAX_FILE_SIZE
      errors.add(:file, "must be smaller than 25 MB")
    end

    content_type = file.blob.content_type.to_s
    return if SUPPORTED_CONTENT_TYPES.include?(content_type)
    return if content_type == "application/octet-stream" && safe_octet_stream_extension?

    errors.add(:file, "must be a CSV, XLS, XLSX, PDF, JPEG, PNG or WebP file")
  end

  def safe_octet_stream_extension?
    extension = File.extname(file.filename.to_s).delete_prefix(".").downcase
    SAFE_OCTET_STREAM_EXTENSIONS.include?(extension)
  end
end
