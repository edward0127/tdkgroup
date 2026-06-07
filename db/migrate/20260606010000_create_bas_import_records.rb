class CreateBasImportRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :bas_import_runs do |t|
      t.references :bas_job, null: false, foreign_key: true
      t.references :bas_document, null: false, foreign_key: true
      t.string :import_type, null: false
      t.string :status, default: "pending", null: false
      t.json :column_mapping, default: {}, null: false
      t.json :preview_rows, default: [], null: false
      t.integer :row_count, default: 0, null: false
      t.integer :imported_count, default: 0, null: false
      t.integer :error_count, default: 0, null: false
      t.json :errors, default: [], null: false
      t.datetime :imported_at
      t.string :imported_by

      t.timestamps
    end

    add_index :bas_import_runs, :import_type
    add_index :bas_import_runs, :status

    create_table :bas_bank_transactions do |t|
      t.references :bas_job, null: false, foreign_key: true
      t.references :bas_import_run, foreign_key: true
      t.date :transaction_date
      t.text :description
      t.text :details
      t.string :reference
      t.decimal :debit, precision: 12, scale: 2
      t.decimal :credit, precision: 12, scale: 2
      t.decimal :amount, precision: 12, scale: 2
      t.decimal :balance, precision: 12, scale: 2
      t.string :bank_account_name
      t.integer :source_row_number
      t.string :status, default: "imported", null: false
      t.text :notes

      t.timestamps
    end

    add_index :bas_bank_transactions, :transaction_date
    add_index :bas_bank_transactions, :status

    create_table :bas_invoices do |t|
      t.references :bas_job, null: false, foreign_key: true
      t.references :bas_import_run, foreign_key: true
      t.string :direction, default: "unknown", null: false
      t.string :invoice_number
      t.date :issue_date
      t.date :paid_date
      t.string :party_name
      t.text :description
      t.decimal :total_amount, precision: 12, scale: 2
      t.decimal :gst_amount, precision: 12, scale: 2
      t.decimal :net_amount, precision: 12, scale: 2
      t.string :payment_method, default: "unknown", null: false
      t.string :gst_code, default: "unknown", null: false
      t.integer :source_row_number
      t.string :status, default: "imported", null: false
      t.text :notes

      t.timestamps
    end

    add_index :bas_invoices, :direction
    add_index :bas_invoices, :gst_code
    add_index :bas_invoices, :status
    add_index :bas_invoices, :issue_date

    create_table :bas_cash_transactions do |t|
      t.references :bas_job, null: false, foreign_key: true
      t.references :bas_import_run, foreign_key: true
      t.date :transaction_date
      t.string :direction, default: "unknown", null: false
      t.string :party_name
      t.text :description
      t.decimal :total_amount, precision: 12, scale: 2
      t.decimal :gst_amount, precision: 12, scale: 2
      t.string :gst_code, default: "unknown", null: false
      t.integer :source_row_number
      t.string :status, default: "imported", null: false
      t.text :notes

      t.timestamps
    end

    add_index :bas_cash_transactions, :transaction_date
    add_index :bas_cash_transactions, :direction
    add_index :bas_cash_transactions, :gst_code
    add_index :bas_cash_transactions, :status

    create_table :bas_payroll_summaries do |t|
      t.references :bas_job, null: false, foreign_key: true
      t.references :bas_import_run, foreign_key: true
      t.decimal :gross_wages, precision: 12, scale: 2
      t.decimal :payg_withheld, precision: 12, scale: 2
      t.decimal :super_amount, precision: 12, scale: 2
      t.integer :source_row_number
      t.text :notes

      t.timestamps
    end
  end
end
