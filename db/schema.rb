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

ActiveRecord::Schema[8.1].define(version: 2026_05_14_090200) do
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
  add_foreign_key "cms_page_translations", "cms_pages"
end
