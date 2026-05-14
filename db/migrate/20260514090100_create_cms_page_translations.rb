class CreateCmsPageTranslations < ActiveRecord::Migration[8.1]
  def change
    create_table :cms_page_translations do |t|
      t.references :cms_page, null: false, foreign_key: true
      t.string :locale, null: false
      t.string :title, null: false
      t.string :seo_title
      t.text :seo_description
      t.json :published_json, null: false, default: {}
      t.json :draft_json, null: false, default: {}
      t.datetime :published_at

      t.timestamps
    end

    add_index :cms_page_translations, [ :cms_page_id, :locale ], unique: true
  end
end
