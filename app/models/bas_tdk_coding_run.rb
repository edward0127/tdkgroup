class BasTdkCodingRun < ApplicationRecord
  STATUS_VALUES = %w[
    queued
    processing
    needs_mapping
    processed
    failed
    superseded
  ].freeze
  TERMINAL_STATUS_VALUES = %w[needs_mapping processed failed superseded].freeze
  COUNT_ATTRIBUTES = %i[
    reference_row_count
    row_count
    suggestion_count
    warning_count
    reviewed_count
  ].freeze

  belongs_to :bas_job, inverse_of: :tdk_coding_runs
  belongs_to :target_workbook,
    class_name: "BasTdkWorkbook",
    inverse_of: :coding_runs

  has_many :row_codings,
    class_name: "BasTdkRowCoding",
    foreign_key: :bas_tdk_coding_run_id,
    dependent: :destroy,
    inverse_of: :coding_run
  has_one_attached :reference_file, dependent: :purge_later

  before_validation :normalize_json_attributes
  before_validation :copy_source_filename_from_reference_file

  validates :status, inclusion: { in: STATUS_VALUES }
  validates :version_number,
    numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :target_workbook_id }
  validates(*COUNT_ATTRIBUTES,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 })
  validates :header_row_number,
    :data_start_row,
    numericality: { only_integer: true, greater_than: 0, allow_nil: true }
  validate :json_attributes_have_expected_shapes
  validate :target_workbook_belongs_to_same_job
  validate :data_starts_after_header
  validate :summary_counts_fit_row_count

  scope :recent, -> { order(version_number: :desc, id: :desc) }
  scope :processed, -> { where(status: "processed") }
  scope :active_processed, -> { processed.recent }
  scope :running, -> { where(status: %w[queued processing]) }

  def queued?
    status == "queued"
  end

  def processing?
    status == "processing"
  end

  def needs_mapping?
    status == "needs_mapping"
  end

  def processed?
    status == "processed"
  end

  def failed?
    status == "failed"
  end

  def superseded?
    status == "superseded"
  end

  def terminal_status?
    TERMINAL_STATUS_VALUES.include?(status)
  end

  def active_processed?
    processed? && target_workbook.coding_runs.active_processed.first&.id == id
  end

  def processing_errors
    row_errors.is_a?(Array) ? row_errors : []
  end

  private

  def normalize_json_attributes
    self.original_headers = [] if original_headers.nil?
    self.column_mapping = {} if column_mapping.nil?
    self.row_errors = [] if row_errors.nil?
    self.metadata = {} if metadata.nil?
  end

  def copy_source_filename_from_reference_file
    return if source_filename.present? || !reference_file.attached?

    self.source_filename = reference_file.filename.to_s
  end

  def json_attributes_have_expected_shapes
    errors.add(:original_headers, "must be a JSON array") unless original_headers.is_a?(Array)
    errors.add(:column_mapping, "must be a JSON object") unless column_mapping.is_a?(Hash)
    errors.add(:row_errors, "must be a JSON array") unless row_errors.is_a?(Array)
    errors.add(:metadata, "must be a JSON object") unless metadata.is_a?(Hash)
  end

  def target_workbook_belongs_to_same_job
    return if bas_job.blank? || target_workbook.blank?
    return if target_workbook.bas_job_id == bas_job_id

    errors.add(:target_workbook, "must belong to the same BAS job")
  end

  def data_starts_after_header
    return if header_row_number.blank? || data_start_row.blank?
    return if data_start_row > header_row_number

    errors.add(:data_start_row, "must be after the header row")
  end

  def summary_counts_fit_row_count
    return if row_count.blank?

    %i[suggestion_count warning_count reviewed_count].each do |attribute|
      value = public_send(attribute)
      next if value.blank? || value <= row_count

      errors.add(attribute, "cannot exceed row count")
    end

    return if warning_count.blank? || reviewed_count.blank?
    return if warning_count + reviewed_count <= row_count

    errors.add(:warning_count, "and reviewed count together cannot exceed row count")
  end
end
