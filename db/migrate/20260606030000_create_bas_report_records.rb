class CreateBasReportRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :bas_adjustments do |t|
      t.references :bas_job, null: false, foreign_key: true
      t.string :adjustment_type, null: false
      t.string :label, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.text :reason, null: false
      t.string :created_by

      t.timestamps
    end

    add_index :bas_adjustments, :adjustment_type

    create_table :bas_report_snapshots do |t|
      t.references :bas_job, null: false, foreign_key: true
      t.string :status, default: "draft", null: false
      t.json :totals, default: {}, null: false
      t.json :validation_errors, default: [], null: false
      t.datetime :generated_at
      t.string :generated_by
      t.datetime :approved_at
      t.string :approved_by
      t.datetime :locked_at
      t.string :locked_by
      t.text :notes

      t.timestamps
    end

    add_index :bas_report_snapshots, :status
    add_index :bas_report_snapshots, :generated_at
  end
end
