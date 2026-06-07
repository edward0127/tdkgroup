class BasPayrollSummary < ApplicationRecord
  belongs_to :bas_job
  belongs_to :bas_import_run, optional: true, inverse_of: :payroll_summaries

  validate :at_least_one_amount_is_present
  validate :import_run_belongs_to_same_job

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  private

  def at_least_one_amount_is_present
    return if gross_wages.present? || payg_withheld.present? || super_amount.present?

    errors.add(:base, "At least one payroll amount must be present")
  end

  def import_run_belongs_to_same_job
    return if bas_job.blank? || bas_import_run.blank?

    errors.add(:bas_import_run, "must belong to the same BAS job") if bas_import_run.bas_job_id != bas_job_id
  end
end
