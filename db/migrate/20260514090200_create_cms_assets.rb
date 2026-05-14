class CreateCmsAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :cms_assets do |t|
      t.string :key, null: false
      t.string :alt_text_en
      t.string :alt_text_zh

      t.timestamps
    end

    add_index :cms_assets, :key, unique: true
  end
end
