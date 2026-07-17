class BasTdkWorkbook < ApplicationRecord
  STATUS_VALUES = %w[queued processing needs_mapping processed failed superseded].freeze
  EXPORT_STATUS_VALUES = %w[not_started queued processing processed failed stale].freeze
  STALE_PROCESSING_AFTER = 30.minutes

  belongs_to :bas_job, inverse_of: :tdk_workbooks
  belongs_to :source_bas_document,
    class_name: "BasDocument",
    optional: true

  has_many :rows,
    class_name: "BasTdkWorkbookRow",
    dependent: :destroy,
    inverse_of: :bas_tdk_workbook
  has_many :coding_runs,
    class_name: "BasTdkCodingRun",
    foreign_key: :target_workbook_id,
    dependent: :destroy,
    inverse_of: :target_workbook
  has_one_attached :source_file, dependent: :purge_later
  has_one_attached :export_file, dependent: :purge_later

  before_validation :normalize_json_attributes

  validates :status, inclusion: { in: STATUS_VALUES }
  validates :export_status, inclusion: { in: EXPORT_STATUS_VALUES }
  validates :version_number, numericality: { only_integer: true, greater_than: 0 }
  validates :row_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent, -> { order(version_number: :desc, id: :desc) }
  scope :processed, -> { where(status: "processed") }
  scope :active_processed, -> { processed.recent }

  def queued?
    status == "queued"
  end

  def processing?
    status == "processing"
  end

  def processed?
    status == "processed"
  end

  def needs_mapping?
    status == "needs_mapping"
  end

  def failed?
    status == "failed"
  end

  def superseded?
    status == "superseded"
  end

  def terminal_status?
    needs_mapping? || processed? || failed? || superseded?
  end

  def active_processed?
    processed? && bas_job.tdk_workbooks.active_processed.first&.id == id
  end

  def processing_stale?
    processing? && processing_started_at.present? && processing_started_at < STALE_PROCESSING_AFTER.ago
  end

  def export_ready?
    export_status == "processed" && export_file.attached?
  end

  def export_in_progress?
    export_status.in?(%w[queued processing])
  end

  def invalidate_export!
    export_file.purge_later if export_file.attached?
    update!(
      export_status: "stale",
      export_error: nil,
      export_generated_at: nil,
      export_started_at: nil,
      export_finished_at: nil
    )
  end

  def download_filename
    basename = File.basename(source_filename.to_s, ".*").parameterize
    basename = "tdk-bank-statement" if basename.blank?
    "#{basename}-latest-v#{version_number}.xlsx"
  end

  def processing_errors
    row_errors.is_a?(Array) ? row_errors : []
  end

  private

  def normalize_json_attributes
    self.original_headers = [] unless original_headers.is_a?(Array)
    self.processed_headers = [] unless processed_headers.is_a?(Array)
    self.row_errors = [] unless row_errors.is_a?(Array)
    self.metadata = {} unless metadata.is_a?(Hash)
  end
end
