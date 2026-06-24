class AddBackgroundStateToBasTdkWorkbooks < ActiveRecord::Migration[8.1]
  def change
    add_column :bas_tdk_workbooks, :processing_started_at, :datetime
    add_column :bas_tdk_workbooks, :processing_finished_at, :datetime
    add_column :bas_tdk_workbooks, :export_status, :string, default: "not_started", null: false
    add_column :bas_tdk_workbooks, :export_started_at, :datetime
    add_column :bas_tdk_workbooks, :export_finished_at, :datetime
    add_column :bas_tdk_workbooks, :export_error, :text
    add_column :bas_tdk_workbooks, :export_generated_at, :datetime
    add_column :bas_tdk_workbooks, :export_requested_by, :string

    add_index :bas_tdk_workbooks, :export_status
  end
end
