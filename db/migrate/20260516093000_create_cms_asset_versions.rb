class CreateCmsAssetVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :cms_asset_versions do |t|
      t.references :cms_asset, null: false, foreign_key: true
      t.string :alt_text_en
      t.string :alt_text_zh
      t.string :admin_identifier

      t.timestamps
    end
  end
end
