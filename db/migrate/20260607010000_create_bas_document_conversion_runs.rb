class CreateBasDocumentConversionRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :bas_document_conversion_runs do |t|
      t.references :bas_job, null: false, foreign_key: true
      t.references :source_bas_document, null: false, foreign_key: { to_table: :bas_documents }
      t.references :bas_import_run, foreign_key: true
      t.string :conversion_type, default: "bank_statement_pdf", null: false
      t.string :status, default: "pending", null: false
      t.string :detected_bank_name
      t.integer :page_count
      t.integer :row_count, default: 0, null: false
      t.integer :converted_count, default: 0, null: false
      t.integer :error_count, default: 0, null: false
      t.json :preview_rows, default: [], null: false
      t.json :row_errors, default: [], null: false
      t.json :metadata, default: {}, null: false
      t.datetime :converted_at
      t.string :converted_by
      t.datetime :imported_at
      t.string :imported_by
      t.datetime :matched_at
      t.string :matched_by

      t.timestamps
    end

    add_index :bas_document_conversion_runs, :conversion_type
    add_index :bas_document_conversion_runs, :status
  end
end
