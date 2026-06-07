class RenameBasAiModelNameColumn < ActiveRecord::Migration[8.1]
  def change
    rename_column :bas_ai_extraction_runs, :model_name, :ai_model_name
  end
end
