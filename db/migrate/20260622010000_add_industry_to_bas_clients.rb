class AddIndustryToBasClients < ActiveRecord::Migration[8.1]
  def change
    add_column :bas_clients, :industry, :string, default: "other", null: false
    add_index :bas_clients, :industry
  end
end
