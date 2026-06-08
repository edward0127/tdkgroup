class BasJob < ApplicationRecord
  CLEANUP_DELETE_BLOCKED_MESSAGE = "This BAS job cannot be deleted because it is locked or has final approved records."
  PROTECTED_CLEANUP_STATUS_VALUES = %w[approved locked final lodged completed].freeze

  STATUS_VALUES = %w[
    draft
    collecting_materials
    ready_for_import
    importing
    matching
    queries_open
    review_ready
    report_ready
    approved
    locked
    cancelled
  ].freeze

  belongs_to :bas_client

  before_destroy :prevent_destroy_unless_cleanup_deletable, prepend: true

  has_many :ai_suggestions,
    class_name: "BasAiSuggestion",
    dependent: :destroy,
    inverse_of: :bas_job
  has_many :ai_extraction_runs,
    class_name: "BasAiExtractionRun",
    dependent: :destroy,
    inverse_of: :bas_job
  has_many :document_conversion_runs,
    class_name: "BasDocumentConversionRun",
    dependent: :destroy,
    inverse_of: :bas_job
  has_many :matches,
    class_name: "BasMatch",
    dependent: :destroy,
    inverse_of: :bas_job
  has_many :bank_transactions,
    class_name: "BasBankTransaction",
    dependent: :destroy,
    inverse_of: :bas_job
  has_many :invoices,
    class_name: "BasInvoice",
    dependent: :destroy,
    inverse_of: :bas_job
  has_many :cash_transactions,
    class_name: "BasCashTransaction",
    dependent: :destroy,
    inverse_of: :bas_job
  has_many :payroll_summaries,
    class_name: "BasPayrollSummary",
    dependent: :destroy,
    inverse_of: :bas_job
  has_many :import_runs,
    class_name: "BasImportRun",
    dependent: :destroy,
    inverse_of: :bas_job
  has_many :documents,
    class_name: "BasDocument",
    dependent: :destroy,
    inverse_of: :bas_job
  has_many :queries,
    class_name: "BasQuery",
    dependent: :destroy,
    inverse_of: :bas_job
  has_many :adjustments,
    class_name: "BasAdjustment",
    dependent: :destroy,
    inverse_of: :bas_job
  has_many :report_snapshots,
    class_name: "BasReportSnapshot",
    dependent: :destroy,
    inverse_of: :bas_job
  has_many :audit_events,
    class_name: "BasAuditEvent",
    dependent: :destroy,
    inverse_of: :bas_job

  before_validation :copy_defaults_from_client, on: :create
  before_validation :generate_quarter_label

  validates :period_start, :period_end, presence: true
  validates :status, inclusion: { in: STATUS_VALUES }
  validates :gst_basis, inclusion: { in: BasClient::GST_BASIS_VALUES }
  validates :reporting_method, inclusion: { in: BasClient::REPORTING_METHOD_VALUES }
  validate :period_start_is_not_after_period_end

  scope :open, -> { where.not(status: %w[approved locked cancelled]) }
  scope :recently_updated, -> { order(updated_at: :desc, id: :desc) }

  def locked?
    status == "locked" || locked_at.present?
  end

  def cleanup_deletable?
    !locked? &&
      !cleanup_protected_status? &&
      !approved_for_cleanup? &&
      !final_or_approved_report_snapshot?
  end

  def cleanup_protected_status?
    PROTECTED_CLEANUP_STATUS_VALUES.include?(status.to_s)
  end

  def approved_for_cleanup?
    approved_at.present? || approved_by.present?
  end

  def final_or_approved_report_snapshot?
    report_snapshots.where(status: "final").exists? ||
      report_snapshots.where.not(approved_at: nil).exists? ||
      report_snapshots.where.not(approved_by: [ nil, "" ]).exists? ||
      report_snapshots.where.not(locked_at: nil).exists? ||
      report_snapshots.where.not(locked_by: [ nil, "" ]).exists?
  end

  def period_label
    return quarter_label if quarter_label.present?
    return "Unscheduled" if period_start.blank? || period_end.blank?

    "#{period_start.to_fs(:db)} to #{period_end.to_fs(:db)}"
  end

  private

  def copy_defaults_from_client
    return if bas_client.blank?

    self.gst_basis = bas_client.default_gst_basis if gst_basis.blank? || gst_basis == "unknown"
    self.reporting_method = bas_client.default_reporting_method if reporting_method.blank? || reporting_method == "unknown"
  end

  def generate_quarter_label
    return if quarter_label.present? || period_start.blank? || period_end.blank?

    self.quarter_label = "FY#{financial_year_end(period_end)} Q#{bas_quarter(period_end)}"
  end

  def financial_year_end(date)
    date.month >= 7 ? date.year + 1 : date.year
  end

  def bas_quarter(date)
    case date.month
    when 7..9 then 1
    when 10..12 then 2
    when 1..3 then 3
    else 4
    end
  end

  def period_start_is_not_after_period_end
    return if period_start.blank? || period_end.blank?

    errors.add(:period_start, "must be before or equal to period end") if period_start > period_end
  end

  def prevent_destroy_unless_cleanup_deletable
    return if cleanup_deletable?

    errors.add(:base, CLEANUP_DELETE_BLOCKED_MESSAGE)
    throw :abort
  end
end
