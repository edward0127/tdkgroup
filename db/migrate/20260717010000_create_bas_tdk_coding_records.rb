class CreateBasTdkCodingRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :bas_tdk_coding_runs do |t|
      t.references :bas_job, null: false, foreign_key: true
      t.references :target_workbook,
        null: false,
        foreign_key: { to_table: :bas_tdk_workbooks }
      t.integer :version_number, default: 1, null: false
      t.string :status, default: "queued", null: false
      t.string :source_filename
      t.string :sheet_name
      t.integer :header_row_number
      t.integer :data_start_row
      t.json :original_headers, default: [], null: false
      t.json :column_mapping, default: {}, null: false
      t.json :row_errors, default: [], null: false
      t.json :metadata, default: {}, null: false
      t.string :ruleset_version
      t.string :requested_by
      t.datetime :processing_started_at
      t.datetime :processing_finished_at
      t.datetime :processed_at
      t.datetime :superseded_at
      t.integer :reference_row_count, default: 0, null: false
      t.integer :row_count, default: 0, null: false
      t.integer :suggestion_count, default: 0, null: false
      t.integer :warning_count, default: 0, null: false
      t.integer :reviewed_count, default: 0, null: false

      t.timestamps
    end

    add_index :bas_tdk_coding_runs, :status
    add_index :bas_tdk_coding_runs,
      [ :target_workbook_id, :version_number ],
      unique: true,
      name: "index_bas_tdk_coding_runs_on_workbook_and_version"

    create_table :bas_tdk_row_codings do |t|
      t.references :bas_tdk_coding_run, null: false, foreign_key: true
      t.references :bas_tdk_workbook_row, null: false, foreign_key: true
      t.string :suggested_category
      t.decimal :suggested_gst_amount, precision: 14, scale: 2
      t.string :gst_treatment, default: "unknown", null: false
      t.string :category_source, default: "unmatched", null: false
      t.string :gst_source, default: "unmatched", null: false
      t.decimal :category_confidence, precision: 5, scale: 2
      t.decimal :gst_confidence, precision: 5, scale: 2
      t.boolean :category_review_required, default: true, null: false
      t.boolean :gst_review_required, default: true, null: false
      t.string :review_status, default: "proposed", null: false
      t.json :warning_codes, default: [], null: false
      t.text :explanation
      t.integer :reference_source_row_number
      t.json :reference_snapshot, default: {}, null: false
      t.json :metadata, default: {}, null: false
      t.string :reviewed_by
      t.datetime :reviewed_at

      t.timestamps
    end

    add_index :bas_tdk_row_codings,
      [ :bas_tdk_coding_run_id, :bas_tdk_workbook_row_id ],
      unique: true,
      name: "index_bas_tdk_row_codings_on_run_and_row"
    add_index :bas_tdk_row_codings,
      [ :bas_tdk_coding_run_id, :review_status ],
      name: "index_bas_tdk_row_codings_on_run_and_review_status"
    add_index :bas_tdk_row_codings,
      [ :bas_tdk_coding_run_id, :category_source ],
      name: "index_bas_tdk_row_codings_on_run_and_category_source"
    add_index :bas_tdk_row_codings,
      [ :bas_tdk_coding_run_id, :gst_source ],
      name: "index_bas_tdk_row_codings_on_run_and_gst_source"
  end
end
