class BasTdkWorkbookRow < ApplicationRecord
  belongs_to :bas_tdk_workbook,
    inverse_of: :rows

  before_validation :normalize_row_data

  validates :position, numericality: { only_integer: true, greater_than: 0 }

  scope :ordered, -> { order(position: :asc, id: :asc) }

  private

  def normalize_row_data
    self.row_data = {} unless row_data.is_a?(Hash)
  end
end
