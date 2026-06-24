class AddWorkflowTypeToBasJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :bas_jobs, :workflow_type, :string, default: "standard", null: false
    add_index :bas_jobs, :workflow_type
  end
end
