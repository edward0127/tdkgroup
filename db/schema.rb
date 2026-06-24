# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_22_013000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "bas_adjustments", force: :cascade do |t|
    t.string "adjustment_type", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.integer "bas_job_id", null: false
    t.datetime "created_at", null: false
    t.string "created_by"
    t.string "label", null: false
    t.text "reason", null: false
    t.datetime "updated_at", null: false
    t.index ["adjustment_type"], name: "index_bas_adjustments_on_adjustment_type"
    t.index ["bas_job_id"], name: "index_bas_adjustments_on_bas_job_id"
  end

  create_table "bas_ai_extraction_runs", force: :cascade do |t|
    t.string "ai_model_name"
    t.integer "bas_document_id"
    t.integer "bas_job_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "input_kind"
    t.json "metadata", default: {}, null: false
    t.string "provider"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.text "summary"
    t.datetime "updated_at", null: false
    t.index ["bas_document_id"], name: "index_bas_ai_extraction_runs_on_bas_document_id"
    t.index ["bas_job_id"], name: "index_bas_ai_extraction_runs_on_bas_job_id"
    t.index ["input_kind"], name: "index_bas_ai_extraction_runs_on_input_kind"
    t.index ["status"], name: "index_bas_ai_extraction_runs_on_status"
  end

  create_table "bas_ai_suggestions", force: :cascade do |t|
    t.datetime "accepted_at"
    t.string "accepted_by"
    t.integer "bas_ai_extraction_run_id", null: false
    t.integer "bas_job_id", null: false
    t.decimal "confidence", precision: 5, scale: 2
    t.datetime "created_at", null: false
    t.text "explanation"
    t.text "notes"
    t.datetime "rejected_at"
    t.string "rejected_by"
    t.integer "source_id"
    t.string "source_type"
    t.string "status", default: "proposed", null: false
    t.json "suggested_data", default: {}, null: false
    t.string "suggestion_type", null: false
    t.datetime "updated_at", null: false
    t.index ["bas_ai_extraction_run_id"], name: "index_bas_ai_suggestions_on_run_id"
    t.index ["bas_job_id"], name: "index_bas_ai_suggestions_on_bas_job_id"
    t.index ["source_type", "source_id"], name: "index_bas_ai_suggestions_on_source_type_and_source_id"
    t.index ["status"], name: "index_bas_ai_suggestions_on_status"
    t.index ["suggestion_type"], name: "index_bas_ai_suggestions_on_suggestion_type"
  end

  create_table "bas_audit_events", force: :cascade do |t|
    t.string "actor_username"
    t.integer "auditable_id"
    t.string "auditable_type"
    t.integer "bas_job_id"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.json "metadata", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["auditable_type", "auditable_id"], name: "index_bas_audit_events_on_auditable"
    t.index ["bas_job_id"], name: "index_bas_audit_events_on_bas_job_id"
    t.index ["event_type"], name: "index_bas_audit_events_on_event_type"
  end

  create_table "bas_bank_transactions", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2
    t.decimal "balance", precision: 12, scale: 2
    t.string "bank_account_name"
    t.integer "bas_import_run_id"
    t.integer "bas_job_id", null: false
    t.datetime "created_at", null: false
    t.decimal "credit", precision: 12, scale: 2
    t.decimal "debit", precision: 12, scale: 2
    t.text "description"
    t.text "details"
    t.text "notes"
    t.string "reference"
    t.integer "source_row_number"
    t.string "status", default: "imported", null: false
    t.date "transaction_date"
    t.datetime "updated_at", null: false
    t.index ["bas_import_run_id"], name: "index_bas_bank_transactions_on_bas_import_run_id"
    t.index ["bas_job_id"], name: "index_bas_bank_transactions_on_bas_job_id"
    t.index ["status"], name: "index_bas_bank_transactions_on_status"
    t.index ["transaction_date"], name: "index_bas_bank_transactions_on_transaction_date"
  end

  create_table "bas_cash_transactions", force: :cascade do |t|
    t.integer "bas_import_run_id"
    t.integer "bas_job_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "direction", default: "unknown", null: false
    t.decimal "gst_amount", precision: 12, scale: 2
    t.string "gst_code", default: "unknown", null: false
    t.text "notes"
    t.string "party_name"
    t.integer "source_row_number"
    t.string "status", default: "imported", null: false
    t.decimal "total_amount", precision: 12, scale: 2
    t.date "transaction_date"
    t.datetime "updated_at", null: false
    t.index ["bas_import_run_id"], name: "index_bas_cash_transactions_on_bas_import_run_id"
    t.index ["bas_job_id"], name: "index_bas_cash_transactions_on_bas_job_id"
    t.index ["direction"], name: "index_bas_cash_transactions_on_direction"
    t.index ["gst_code"], name: "index_bas_cash_transactions_on_gst_code"
    t.index ["status"], name: "index_bas_cash_transactions_on_status"
    t.index ["transaction_date"], name: "index_bas_cash_transactions_on_transaction_date"
  end

  create_table "bas_clients", force: :cascade do |t|
    t.string "abn"
    t.boolean "archived", default: false, null: false
    t.string "contact_email"
    t.string "contact_name"
    t.string "contact_phone"
    t.datetime "created_at", null: false
    t.string "default_gst_basis", default: "unknown", null: false
    t.string "default_reporting_method", default: "unknown", null: false
    t.string "industry", default: "other", null: false
    t.string "legal_name", null: false
    t.text "notes"
    t.string "reporting_frequency", default: "quarterly", null: false
    t.string "trading_name"
    t.datetime "updated_at", null: false
    t.index ["archived"], name: "index_bas_clients_on_archived"
    t.index ["industry"], name: "index_bas_clients_on_industry"
    t.index ["legal_name"], name: "index_bas_clients_on_legal_name"
  end

  create_table "bas_document_conversion_runs", force: :cascade do |t|
    t.integer "bas_import_run_id"
    t.integer "bas_job_id", null: false
    t.string "conversion_type", default: "bank_statement_pdf", null: false
    t.datetime "converted_at"
    t.string "converted_by"
    t.integer "converted_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "detected_bank_name"
    t.integer "error_count", default: 0, null: false
    t.datetime "imported_at"
    t.string "imported_by"
    t.datetime "matched_at"
    t.string "matched_by"
    t.json "metadata", default: {}, null: false
    t.integer "page_count"
    t.json "preview_rows", default: [], null: false
    t.integer "row_count", default: 0, null: false
    t.json "row_errors", default: [], null: false
    t.integer "source_bas_document_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["bas_import_run_id"], name: "index_bas_document_conversion_runs_on_bas_import_run_id"
    t.index ["bas_job_id"], name: "index_bas_document_conversion_runs_on_bas_job_id"
    t.index ["conversion_type"], name: "index_bas_document_conversion_runs_on_conversion_type"
    t.index ["source_bas_document_id"], name: "index_bas_document_conversion_runs_on_source_bas_document_id"
    t.index ["status"], name: "index_bas_document_conversion_runs_on_status"
  end

  create_table "bas_documents", force: :cascade do |t|
    t.integer "bas_job_id", null: false
    t.datetime "created_at", null: false
    t.string "document_type", default: "other", null: false
    t.json "metadata", default: {}, null: false
    t.text "notes"
    t.string "processing_status", default: "not_processed", null: false
    t.string "source_filename"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "uploaded_by"
    t.index ["bas_job_id"], name: "index_bas_documents_on_bas_job_id"
    t.index ["document_type"], name: "index_bas_documents_on_document_type"
    t.index ["processing_status"], name: "index_bas_documents_on_processing_status"
  end

  create_table "bas_import_runs", force: :cascade do |t|
    t.integer "bas_document_id", null: false
    t.integer "bas_job_id", null: false
    t.json "column_mapping", default: {}, null: false
    t.datetime "created_at", null: false
    t.integer "error_count", default: 0, null: false
    t.string "import_type", null: false
    t.datetime "imported_at"
    t.string "imported_by"
    t.integer "imported_count", default: 0, null: false
    t.json "preview_rows", default: [], null: false
    t.integer "row_count", default: 0, null: false
    t.json "row_errors", default: [], null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["bas_document_id"], name: "index_bas_import_runs_on_bas_document_id"
    t.index ["bas_job_id"], name: "index_bas_import_runs_on_bas_job_id"
    t.index ["import_type"], name: "index_bas_import_runs_on_import_type"
    t.index ["status"], name: "index_bas_import_runs_on_status"
  end

  create_table "bas_invoices", force: :cascade do |t|
    t.integer "bas_import_run_id"
    t.integer "bas_job_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "direction", default: "unknown", null: false
    t.decimal "gst_amount", precision: 12, scale: 2
    t.string "gst_code", default: "unknown", null: false
    t.string "invoice_number"
    t.date "issue_date"
    t.decimal "net_amount", precision: 12, scale: 2
    t.text "notes"
    t.date "paid_date"
    t.string "party_name"
    t.string "payment_method", default: "unknown", null: false
    t.integer "source_row_number"
    t.string "status", default: "imported", null: false
    t.decimal "total_amount", precision: 12, scale: 2
    t.datetime "updated_at", null: false
    t.index ["bas_import_run_id"], name: "index_bas_invoices_on_bas_import_run_id"
    t.index ["bas_job_id"], name: "index_bas_invoices_on_bas_job_id"
    t.index ["direction"], name: "index_bas_invoices_on_direction"
    t.index ["gst_code"], name: "index_bas_invoices_on_gst_code"
    t.index ["issue_date"], name: "index_bas_invoices_on_issue_date"
    t.index ["status"], name: "index_bas_invoices_on_status"
  end

  create_table "bas_jobs", force: :cascade do |t|
    t.datetime "approved_at"
    t.string "approved_by"
    t.integer "bas_client_id", null: false
    t.boolean "cash_transactions_applicable", default: false, null: false
    t.datetime "created_at", null: false
    t.string "gst_basis", default: "unknown", null: false
    t.text "internal_notes"
    t.datetime "locked_at"
    t.string "locked_by"
    t.boolean "payroll_applicable", default: false, null: false
    t.date "period_end", null: false
    t.date "period_start", null: false
    t.string "quarter_label"
    t.string "reporting_method", default: "unknown", null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.string "workflow_type", default: "standard", null: false
    t.index ["bas_client_id"], name: "index_bas_jobs_on_bas_client_id"
    t.index ["period_start", "period_end"], name: "index_bas_jobs_on_period_start_and_period_end"
    t.index ["status"], name: "index_bas_jobs_on_status"
    t.index ["workflow_type"], name: "index_bas_jobs_on_workflow_type"
  end

  create_table "bas_match_items", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2
    t.integer "bas_match_id", null: false
    t.datetime "created_at", null: false
    t.integer "matchable_id", null: false
    t.string "matchable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["bas_match_id"], name: "index_bas_match_items_on_bas_match_id"
    t.index ["matchable_type", "matchable_id", "bas_match_id"], name: "index_bas_match_items_on_matchable_and_match"
    t.index ["matchable_type", "matchable_id"], name: "index_bas_match_items_on_matchable"
  end

  create_table "bas_matches", force: :cascade do |t|
    t.datetime "accepted_at"
    t.string "accepted_by"
    t.integer "bas_job_id", null: false
    t.decimal "confidence", precision: 5, scale: 2
    t.datetime "created_at", null: false
    t.string "created_by_rule"
    t.text "explanation"
    t.string "match_type", null: false
    t.decimal "matched_amount", precision: 12, scale: 2
    t.text "notes"
    t.datetime "rejected_at"
    t.string "rejected_by"
    t.string "status", default: "proposed", null: false
    t.datetime "updated_at", null: false
    t.index ["bas_job_id"], name: "index_bas_matches_on_bas_job_id"
    t.index ["match_type"], name: "index_bas_matches_on_match_type"
    t.index ["status"], name: "index_bas_matches_on_status"
  end

  create_table "bas_payroll_summaries", force: :cascade do |t|
    t.integer "bas_import_run_id"
    t.integer "bas_job_id", null: false
    t.datetime "created_at", null: false
    t.decimal "gross_wages", precision: 12, scale: 2
    t.text "notes"
    t.decimal "payg_withheld", precision: 12, scale: 2
    t.integer "source_row_number"
    t.decimal "super_amount", precision: 12, scale: 2
    t.datetime "updated_at", null: false
    t.index ["bas_import_run_id"], name: "index_bas_payroll_summaries_on_bas_import_run_id"
    t.index ["bas_job_id"], name: "index_bas_payroll_summaries_on_bas_job_id"
  end

  create_table "bas_queries", force: :cascade do |t|
    t.boolean "auto_generated", default: false, null: false
    t.integer "bas_job_id", null: false
    t.datetime "created_at", null: false
    t.string "created_by"
    t.string "dedupe_key"
    t.text "details"
    t.string "generated_by_rule"
    t.string "query_type", default: "other", null: false
    t.text "resolution_notes"
    t.datetime "resolved_at"
    t.integer "source_id"
    t.string "source_type"
    t.string "status", default: "open", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "updated_by"
    t.index ["bas_job_id", "dedupe_key"], name: "index_bas_queries_on_bas_job_id_and_dedupe_key"
    t.index ["bas_job_id"], name: "index_bas_queries_on_bas_job_id"
    t.index ["query_type"], name: "index_bas_queries_on_query_type"
    t.index ["status"], name: "index_bas_queries_on_status"
  end

  create_table "bas_report_snapshots", force: :cascade do |t|
    t.datetime "approved_at"
    t.string "approved_by"
    t.integer "bas_job_id", null: false
    t.datetime "created_at", null: false
    t.datetime "generated_at"
    t.string "generated_by"
    t.datetime "locked_at"
    t.string "locked_by"
    t.text "notes"
    t.string "status", default: "draft", null: false
    t.json "totals", default: {}, null: false
    t.datetime "updated_at", null: false
    t.json "validation_errors", default: [], null: false
    t.index ["bas_job_id"], name: "index_bas_report_snapshots_on_bas_job_id"
    t.index ["generated_at"], name: "index_bas_report_snapshots_on_generated_at"
    t.index ["status"], name: "index_bas_report_snapshots_on_status"
  end

  create_table "bas_tdk_workbook_rows", force: :cascade do |t|
    t.integer "bas_tdk_workbook_id", null: false
    t.datetime "created_at", null: false
    t.integer "position", null: false
    t.json "row_data", default: {}, null: false
    t.integer "source_row_number"
    t.datetime "updated_at", null: false
    t.index ["bas_tdk_workbook_id", "position"], name: "index_bas_tdk_rows_on_workbook_and_position", unique: true
    t.index ["bas_tdk_workbook_id"], name: "index_bas_tdk_workbook_rows_on_bas_tdk_workbook_id"
  end

  create_table "bas_tdk_workbooks", force: :cascade do |t|
    t.integer "bas_job_id", null: false
    t.datetime "created_at", null: false
    t.text "export_error"
    t.datetime "export_finished_at"
    t.datetime "export_generated_at"
    t.string "export_requested_by"
    t.datetime "export_started_at"
    t.string "export_status", default: "not_started", null: false
    t.integer "header_row_number"
    t.json "metadata", default: {}, null: false
    t.json "original_headers", default: [], null: false
    t.datetime "processed_at"
    t.string "processed_by"
    t.json "processed_headers", default: [], null: false
    t.datetime "processing_finished_at"
    t.datetime "processing_started_at"
    t.integer "row_count", default: 0, null: false
    t.json "row_errors", default: [], null: false
    t.string "sheet_name"
    t.integer "source_bas_document_id"
    t.string "source_filename"
    t.string "status", default: "processed", null: false
    t.datetime "superseded_at"
    t.datetime "updated_at", null: false
    t.integer "version_number", default: 1, null: false
    t.index ["bas_job_id", "version_number"], name: "index_bas_tdk_workbooks_on_bas_job_id_and_version_number", unique: true
    t.index ["bas_job_id"], name: "index_bas_tdk_workbooks_on_bas_job_id"
    t.index ["export_status"], name: "index_bas_tdk_workbooks_on_export_status"
    t.index ["source_bas_document_id"], name: "index_bas_tdk_workbooks_on_source_bas_document_id"
    t.index ["status"], name: "index_bas_tdk_workbooks_on_status"
  end

  create_table "cms_asset_versions", force: :cascade do |t|
    t.string "admin_identifier"
    t.string "alt_text_en"
    t.string "alt_text_zh"
    t.integer "cms_asset_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cms_asset_id"], name: "index_cms_asset_versions_on_cms_asset_id"
  end

  create_table "cms_assets", force: :cascade do |t|
    t.string "alt_text_en"
    t.string "alt_text_zh"
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_cms_assets_on_key", unique: true
  end

  create_table "cms_page_translations", force: :cascade do |t|
    t.integer "cms_page_id", null: false
    t.datetime "created_at", null: false
    t.json "draft_json", default: {}, null: false
    t.string "locale", null: false
    t.datetime "published_at"
    t.json "published_json", default: {}, null: false
    t.text "seo_description"
    t.string "seo_title"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["cms_page_id", "locale"], name: "index_cms_page_translations_on_cms_page_id_and_locale", unique: true
    t.index ["cms_page_id"], name: "index_cms_page_translations_on_cms_page_id"
  end

  create_table "cms_pages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "show_in_footer", default: true, null: false
    t.boolean "show_in_nav", default: true, null: false
    t.string "slug", null: false
    t.integer "sort_order", default: 0, null: false
    t.string "template", default: "standard", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_cms_pages_on_slug", unique: true
    t.index ["sort_order"], name: "index_cms_pages_on_sort_order"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "bas_adjustments", "bas_jobs"
  add_foreign_key "bas_ai_extraction_runs", "bas_documents"
  add_foreign_key "bas_ai_extraction_runs", "bas_jobs"
  add_foreign_key "bas_ai_suggestions", "bas_ai_extraction_runs"
  add_foreign_key "bas_ai_suggestions", "bas_jobs"
  add_foreign_key "bas_audit_events", "bas_jobs"
  add_foreign_key "bas_bank_transactions", "bas_import_runs"
  add_foreign_key "bas_bank_transactions", "bas_jobs"
  add_foreign_key "bas_cash_transactions", "bas_import_runs"
  add_foreign_key "bas_cash_transactions", "bas_jobs"
  add_foreign_key "bas_document_conversion_runs", "bas_documents", column: "source_bas_document_id"
  add_foreign_key "bas_document_conversion_runs", "bas_import_runs"
  add_foreign_key "bas_document_conversion_runs", "bas_jobs"
  add_foreign_key "bas_documents", "bas_jobs"
  add_foreign_key "bas_import_runs", "bas_documents"
  add_foreign_key "bas_import_runs", "bas_jobs"
  add_foreign_key "bas_invoices", "bas_import_runs"
  add_foreign_key "bas_invoices", "bas_jobs"
  add_foreign_key "bas_jobs", "bas_clients"
  add_foreign_key "bas_match_items", "bas_matches"
  add_foreign_key "bas_matches", "bas_jobs"
  add_foreign_key "bas_payroll_summaries", "bas_import_runs"
  add_foreign_key "bas_payroll_summaries", "bas_jobs"
  add_foreign_key "bas_queries", "bas_jobs"
  add_foreign_key "bas_report_snapshots", "bas_jobs"
  add_foreign_key "bas_tdk_workbook_rows", "bas_tdk_workbooks"
  add_foreign_key "bas_tdk_workbooks", "bas_documents", column: "source_bas_document_id"
  add_foreign_key "bas_tdk_workbooks", "bas_jobs"
  add_foreign_key "cms_asset_versions", "cms_assets"
  add_foreign_key "cms_page_translations", "cms_pages"
end
