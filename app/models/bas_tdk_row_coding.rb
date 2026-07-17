class BasTdkRowCoding < ApplicationRecord
  SOURCE_VALUES = %w[
    previous_quarter_exact
    previous_quarter_fuzzy
    rule
    manual
    unmatched
  ].freeze
  REVIEW_STATUS_VALUES = %w[proposed accepted edited needs_review].freeze
  REVIEWED_STATUS_VALUES = %w[accepted edited].freeze
  GST_TREATMENT_VALUES = BasInvoice::GST_CODE_VALUES.freeze
  ZERO_GST_TREATMENT_VALUES = %w[gst_free input_taxed no_gst bas_excluded].freeze
  NIL_GST_TREATMENT_VALUES = %w[needs_review unknown].freeze

  belongs_to :coding_run,
    class_name: "BasTdkCodingRun",
    foreign_key: :bas_tdk_coding_run_id,
    inverse_of: :row_codings
  belongs_to :workbook_row,
    class_name: "BasTdkWorkbookRow",
    foreign_key: :bas_tdk_workbook_row_id,
    inverse_of: :row_codings

  before_validation :normalize_json_attributes

  validates :workbook_row,
    uniqueness: {
      scope: :bas_tdk_coding_run_id,
      message: "already has coding for this run"
    }
  validates :gst_treatment, inclusion: { in: GST_TREATMENT_VALUES }
  validates :category_source, :gst_source, inclusion: { in: SOURCE_VALUES }
  validates :review_status, inclusion: { in: REVIEW_STATUS_VALUES }
  validates :category_confidence,
    :gst_confidence,
    numericality: {
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100,
      allow_nil: true
    }
  validates :suggested_gst_amount, numericality: { allow_nil: true }
  validates :category_review_required,
    :gst_review_required,
    inclusion: { in: [ true, false ] }
  validates :reference_source_row_number,
    numericality: { only_integer: true, greater_than: 0, allow_nil: true }
  validate :json_attributes_have_expected_shapes
  validate :workbook_row_belongs_to_target_workbook
  validate :review_details_are_consistent
  validate :gst_amount_matches_treatment

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :reviewed, -> { where(review_status: REVIEWED_STATUS_VALUES) }
  scope :requiring_review, -> {
    where(category_review_required: true).or(where(gst_review_required: true))
  }
  scope :from_rules, -> {
    where(category_source: "rule").or(where(gst_source: "rule"))
  }

  def warning?
    warning_codes.is_a?(Array) && warning_codes.any?
  end

  def review_required?
    category_review_required? || gst_review_required?
  end

  def reviewed?
    REVIEWED_STATUS_VALUES.include?(review_status)
  end

  private

  def normalize_json_attributes
    self.warning_codes = [] if warning_codes.nil?
    self.reference_snapshot = {} if reference_snapshot.nil?
    self.metadata = {} if metadata.nil?
  end

  def json_attributes_have_expected_shapes
    errors.add(:warning_codes, "must be a JSON array") unless warning_codes.is_a?(Array)
    errors.add(:reference_snapshot, "must be a JSON object") unless reference_snapshot.is_a?(Hash)
    errors.add(:metadata, "must be a JSON object") unless metadata.is_a?(Hash)
  end

  def workbook_row_belongs_to_target_workbook
    return if coding_run.blank? || workbook_row.blank?
    return if workbook_row.bas_tdk_workbook_id == coding_run.target_workbook_id

    errors.add(:workbook_row, "must belong to the coding run target workbook")
  end

  def review_details_are_consistent
    if review_status == "needs_review"
      unless review_required?
        errors.add(:review_status, "requires at least one field to need review")
      end
      reject_review_details
    elsif review_status == "proposed"
      errors.add(:category_review_required, "must be false for an unflagged proposal") unless category_review_required == false
      errors.add(:gst_review_required, "must be false for an unflagged proposal") unless gst_review_required == false
      reject_review_details
    elsif reviewed?
      errors.add(:category_review_required, "must be false for reviewed coding") unless category_review_required == false
      errors.add(:gst_review_required, "must be false for reviewed coding") unless gst_review_required == false
      errors.add(:reviewed_by, "must be present for reviewed coding") if reviewed_by.blank?
      errors.add(:reviewed_at, "must be present for reviewed coding") if reviewed_at.blank?
    end
  end

  def reject_review_details
    return if reviewed_by.blank? && reviewed_at.blank?

    errors.add(:review_status, "must be accepted or edited when review details are recorded")
  end

  def gst_amount_matches_treatment
    case gst_treatment
    when *ZERO_GST_TREATMENT_VALUES
      unless suggested_gst_amount&.zero?
        errors.add(:suggested_gst_amount, "must be zero for #{gst_treatment} treatment")
      end
    when "taxable"
      if suggested_gst_amount.nil?
        errors.add(:suggested_gst_amount, "must be present for taxable treatment")
      end
    when *NIL_GST_TREATMENT_VALUES
      if suggested_gst_amount.present?
        errors.add(:suggested_gst_amount, "must be blank for #{gst_treatment} treatment")
      end
    end
  end
end
