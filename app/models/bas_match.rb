class BasMatch < ApplicationRecord
  MATCH_TYPE_VALUES = %w[
    invoice_to_bank_transaction
    invoices_to_bank_transaction
    invoice_to_cash_transaction
    manual
    ignored
  ].freeze

  STATUS_VALUES = %w[proposed accepted rejected needs_review].freeze

  belongs_to :bas_job
  has_many :items,
    class_name: "BasMatchItem",
    dependent: :destroy,
    inverse_of: :bas_match

  validates :match_type, inclusion: { in: MATCH_TYPE_VALUES }
  validates :status, inclusion: { in: STATUS_VALUES }
  validates :confidence,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100, allow_nil: true }

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :proposed, -> { where(status: "proposed") }
  scope :accepted, -> { where(status: "accepted") }
  scope :rejected, -> { where(status: "rejected") }
  scope :needs_review, -> { where(status: "needs_review") }

  accepts_nested_attributes_for :items

  def accepted?
    status == "accepted"
  end

  def rejected?
    status == "rejected"
  end
end
