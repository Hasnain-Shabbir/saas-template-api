# Partial index: only archived users are in it, so it stays tiny and serves the "show archived users" filter of the admin list.
class AddUsersArchivedAtIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :users, :archived_at, where: "archived_at IS NOT NULL", algorithm: :concurrently
  end
end
