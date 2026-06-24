class CreateBasTdkWorkbooks < ActiveRecord::Migration[8.1]
  def change
    create_table :bas_tdk_workbooks do |t|
      t.references :bas_job, null: false, foreign_key: true
      t.references :source_bas_document, foreign_key: { to_table: :bas_documents }
      t.string :status, default: "processed", null: false
      t.string :source_filename
      t.string :sheet_name
      t.integer :header_row_number
      t.json :original_headers, default: [], null: false
      t.json :processed_headers, default: [], null: false
      t.integer :row_count, default: 0, null: false
      t.json :row_errors, default: [], null: false
      t.json :metadata, default: {}, null: false
      t.integer :version_number, default: 1, null: false
      t.datetime :processed_at
      t.string :processed_by
      t.datetime :superseded_at

      t.timestamps
    end

    add_index :bas_tdk_workbooks, :status
    add_index :bas_tdk_workbooks, [ :bas_job_id, :version_number ], unique: true

    create_table :bas_tdk_workbook_rows do |t|
      t.references :bas_tdk_workbook, null: false, foreign_key: true
      t.integer :position, null: false
      t.integer :source_row_number
      t.json :row_data, default: {}, null: false

      t.timestamps
    end

    add_index :bas_tdk_workbook_rows, [ :bas_tdk_workbook_id, :position ], unique: true, name: "index_bas_tdk_rows_on_workbook_and_position"
  end
end
