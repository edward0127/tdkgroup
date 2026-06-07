class CreateBasFoundation < ActiveRecord::Migration[8.1]
  def change
    create_table :bas_clients do |t|
      t.string :legal_name, null: false
      t.string :trading_name
      t.string :abn
      t.string :contact_name
      t.string :contact_email
      t.string :contact_phone
      t.string :default_gst_basis, default: "unknown", null: false
      t.string :reporting_frequency, default: "quarterly", null: false
      t.string :default_reporting_method, default: "unknown", null: false
      t.text :notes
      t.boolean :archived, default: false, null: false

      t.timestamps
    end

    add_index :bas_clients, :legal_name
    add_index :bas_clients, :archived

    create_table :bas_jobs do |t|
      t.references :bas_client, null: false, foreign_key: true
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.string :quarter_label
      t.string :status, default: "draft", null: false
      t.string :gst_basis, default: "unknown", null: false
      t.string :reporting_method, default: "unknown", null: false
      t.boolean :payroll_applicable, default: false, null: false
      t.boolean :cash_transactions_applicable, default: false, null: false
      t.text :internal_notes
      t.datetime :approved_at
      t.string :approved_by
      t.datetime :locked_at
      t.string :locked_by

      t.timestamps
    end

    add_index :bas_jobs, :status
    add_index :bas_jobs, [ :period_start, :period_end ]

    create_table :bas_documents do |t|
      t.references :bas_job, null: false, foreign_key: true
      t.string :document_type, default: "other", null: false
      t.string :title, null: false
      t.string :source_filename
      t.string :uploaded_by
      t.string :processing_status, default: "not_processed", null: false
      t.json :metadata, default: {}, null: false
      t.text :notes

      t.timestamps
    end

    add_index :bas_documents, :document_type
    add_index :bas_documents, :processing_status

    create_table :bas_queries do |t|
      t.references :bas_job, null: false, foreign_key: true
      t.string :query_type, default: "other", null: false
      t.string :status, default: "open", null: false
      t.string :title, null: false
      t.text :details
      t.text :resolution_notes
      t.datetime :resolved_at
      t.string :created_by
      t.string :updated_by

      t.timestamps
    end

    add_index :bas_queries, :status
    add_index :bas_queries, :query_type

    create_table :bas_audit_events do |t|
      t.references :bas_job, foreign_key: true
      t.references :auditable, polymorphic: true
      t.string :event_type, null: false
      t.string :actor_username
      t.json :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :bas_audit_events, :event_type
  end
end
