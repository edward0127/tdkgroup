class BasQuery < ApplicationRecord
  QUERY_TYPE_VALUES = %w[
    missing_invoice
    missing_receipt
    unmatched_bank_transaction
    unmatched_invoice
    amount_mismatch
    invoice_direction_unclear
    cash_transaction_direction_unclear
    gst_treatment_unclear
    private_use_unclear
    payroll_unclear
    cash_transaction_unclear
    supporting_document_missing
    import_error
    possible_duplicate
    unreviewed_gst_code
    other
  ].freeze

  STATUS_VALUES = %w[
    open
    waiting_for_client
    resolved
    dismissed
  ].freeze

  CLOSED_STATUS_VALUES = %w[resolved dismissed].freeze

  belongs_to :bas_job, inverse_of: :queries

  before_save :set_resolved_timestamp

  validates :title, presence: true
  validates :query_type, inclusion: { in: QUERY_TYPE_VALUES }
  validates :status, inclusion: { in: STATUS_VALUES }
  validates :dedupe_key, uniqueness: { scope: :bas_job_id, allow_blank: true }
  validate :resolution_notes_are_present_when_closed

  scope :open_items, -> { where(status: %w[open waiting_for_client]) }
  scope :recent, -> { order(updated_at: :desc, id: :desc) }

  def closed?
    CLOSED_STATUS_VALUES.include?(status)
  end

  def source_record
    return nil if source_type.blank? || source_id.blank?

    @source_record ||= case source_type
    when "BasBankTransaction"
      bas_job.bank_transactions.find_by(id: source_id)
    when "BasInvoice"
      bas_job.invoices.find_by(id: source_id)
    when "BasCashTransaction"
      bas_job.cash_transactions.find_by(id: source_id)
    when "BasPayrollSummary"
      bas_job.payroll_summaries.find_by(id: source_id)
    when "BasImportRun"
      bas_job.import_runs.includes(:bas_document).find_by(id: source_id)
    when "BasJob"
      bas_job.id == source_id ? bas_job : nil
    else
      nil
    end
  end

  def display_title
    return title if source_record.blank?
    return title if title_has_source_context?

    parts = [
      title.presence || query_type.to_s.humanize,
      source_party_description,
      formatted_source_amount
    ].compact_blank

    return title if parts.size <= 1

    parts.join("  ")
  end

  def source_summary
    source = source_record
    return nil if source.blank?

    parts = [
      source_party_description,
      source_reference,
      source_date&.to_fs(:db)
    ].compact_blank

    parts.join("  ").presence
  end

  def source_type_label
    raw_type = source_record&.class&.name&.demodulize || source_type.to_s.demodulize.presence
    raw_type&.delete_prefix("Bas")&.titleize
  end

  def source_date
    source = source_record

    case source
    when BasBankTransaction, BasCashTransaction
      source.transaction_date
    when BasInvoice
      source.issue_date
    else
      nil
    end
  end

  def source_party_description
    source = source_record

    case source
    when BasBankTransaction
      first_present(source.description, source.details, source.reference, "Bank transaction ##{source.id}")
    when BasInvoice
      first_present(source.party_name, source.description, source.invoice_number, "Invoice ##{source.id}")
    when BasCashTransaction
      first_present(source.party_name, source.description, "Cash transaction ##{source.id}")
    when BasPayrollSummary
      "Payroll summary ##{source.id}"
    when BasImportRun
      first_present(source.bas_document&.title, "Import run ##{source.id}")
    when BasJob
      source.period_label
    else
      nil
    end
  end

  def source_reference
    source = source_record

    case source
    when BasBankTransaction
      source.reference
    when BasInvoice
      source.invoice_number
    when BasImportRun
      "Import run ##{source.id}"
    else
      nil
    end
  end

  def source_amount
    source = source_record

    case source
    when BasBankTransaction
      source.amount
    when BasInvoice, BasCashTransaction
      source.total_amount
    when BasPayrollSummary
      source.gross_wages
    else
      nil
    end
  end

  def source_status_label
    case source_resolution_state
    when "ignored" then "Ignored"
    when "excluded" then "BAS-excluded"
    when "matched" then "Matched"
    else
      source_record.respond_to?(:status) ? source_record.status.to_s.humanize : nil
    end
  end

  def source_resolved?
    source_resolution_state.present?
  end

  def source_resolution_state
    source = source_record
    return nil if source.blank?
    return "ignored" if source.respond_to?(:status) && source.status == "ignored"
    return "excluded" if source.respond_to?(:gst_code) && source.gst_code == "bas_excluded"
    return "matched" if source.respond_to?(:status) && source.status == "matched"
    return "matched" if source.respond_to?(:matches) && source.matches.accepted.exists?

    nil
  end

  private

  def formatted_source_amount
    return nil if source_amount.blank?

    amount = BigDecimal(source_amount.to_s).round(2)
    sign = amount.negative? ? "-" : ""
    integer_part, decimal_part = amount.abs.to_s("F").split(".", 2)
    "#{sign}$#{integer_part}.#{decimal_part.to_s.ljust(2, '0')[0, 2]}"
  end

  def first_present(*values)
    values.map { |value| value.to_s.squish }.find(&:present?)
  end

  def title_has_source_context?
    source_bits = [ source_party_description, formatted_source_amount ].compact_blank
    source_bits.any? { |bit| title.to_s.include?(bit) }
  end

  def resolution_notes_are_present_when_closed
    return unless closed?

    errors.add(:resolution_notes, "must be provided when resolving or dismissing a query") if resolution_notes.blank?
  end

  def set_resolved_timestamp
    if closed?
      self.resolved_at ||= Time.current
    elsif will_save_change_to_status?
      self.resolved_at = nil
    end
  end
end
