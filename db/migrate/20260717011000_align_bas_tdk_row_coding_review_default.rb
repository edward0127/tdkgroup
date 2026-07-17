class AlignBasTdkRowCodingReviewDefault < ActiveRecord::Migration[8.1]
  def up
    change_column_default :bas_tdk_row_codings, :review_status, from: "proposed", to: "needs_review"
    execute <<~SQL.squish
      UPDATE bas_tdk_row_codings
      SET review_status = 'needs_review'
      WHERE review_status = 'proposed'
        AND (category_review_required = 1 OR gst_review_required = 1)
    SQL
  end

  def down
    change_column_default :bas_tdk_row_codings, :review_status, from: "needs_review", to: "proposed"
  end
end
