class CreateBasMatchesAndQuerySources < ActiveRecord::Migration[8.1]
  def change
    create_table :bas_matches do |t|
      t.references :bas_job, null: false, foreign_key: true
      t.string :match_type, null: false
      t.string :status, default: "proposed", null: false
      t.decimal :confidence, precision: 5, scale: 2
      t.decimal :matched_amount, precision: 12, scale: 2
      t.text :explanation
      t.string :created_by_rule
      t.datetime :accepted_at
      t.string :accepted_by
      t.datetime :rejected_at
      t.string :rejected_by
      t.text :notes

      t.timestamps
    end

    add_index :bas_matches, :match_type
    add_index :bas_matches, :status

    create_table :bas_match_items do |t|
      t.references :bas_match, null: false, foreign_key: true
      t.references :matchable, polymorphic: true, null: false
      t.decimal :amount, precision: 12, scale: 2

      t.timestamps
    end

    add_index :bas_match_items,
      [ :matchable_type, :matchable_id, :bas_match_id ],
      name: "index_bas_match_items_on_matchable_and_match"

    change_table :bas_queries do |t|
      t.string :source_type
      t.integer :source_id
      t.string :dedupe_key
      t.string :generated_by_rule
      t.boolean :auto_generated, default: false, null: false
    end

    add_index :bas_queries, [ :bas_job_id, :dedupe_key ]
  end
end
