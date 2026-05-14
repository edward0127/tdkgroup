class CreateCmsPages < ActiveRecord::Migration[8.1]
  def change
    create_table :cms_pages do |t|
      t.string :slug, null: false
      t.string :template, null: false, default: "standard"
      t.boolean :show_in_nav, null: false, default: true
      t.boolean :show_in_footer, null: false, default: true
      t.integer :sort_order, null: false, default: 0

      t.timestamps
    end

    add_index :cms_pages, :slug, unique: true
    add_index :cms_pages, :sort_order
  end
end
