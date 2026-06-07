class RenameBasImportRunErrorsToRowErrors < ActiveRecord::Migration[8.1]
  def change
    rename_column :bas_import_runs, :errors, :row_errors
  end
end
