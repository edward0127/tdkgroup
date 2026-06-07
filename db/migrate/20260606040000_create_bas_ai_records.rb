class CreateBasAiRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :bas_ai_extraction_runs do |t|
      t.references :bas_job, null: false, foreign_key: true
      t.references :bas_document, null: true, foreign_key: true
      t.string :status, default: "pending", null: false
      t.string :provider
      t.string :model_name
      t.string :input_kind
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.text :summary
      t.json :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :bas_ai_extraction_runs, :status
    add_index :bas_ai_extraction_runs, :input_kind

    create_table :bas_ai_suggestions do |t|
      t.references :bas_job, null: false, foreign_key: true
      t.references :bas_ai_extraction_run, null: false, foreign_key: true, index: { name: "index_bas_ai_suggestions_on_run_id" }
      t.string :suggestion_type, null: false
      t.string :status, default: "proposed", null: false
      t.decimal :confidence, precision: 5, scale: 2
      t.string :source_type
      t.integer :source_id
      t.json :suggested_data, default: {}, null: false
      t.text :explanation
      t.datetime :accepted_at
      t.string :accepted_by
      t.datetime :rejected_at
      t.string :rejected_by
      t.text :notes

      t.timestamps
    end

    add_index :bas_ai_suggestions, :suggestion_type
    add_index :bas_ai_suggestions, :status
    add_index :bas_ai_suggestions, [ :source_type, :source_id ]
  end
end
