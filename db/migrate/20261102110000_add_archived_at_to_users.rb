# Layer 3, step 2: a super_admin can archive a user. A timestamp, not a boolean, because it also says when. NULL means active.
class AddArchivedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :archived_at, :datetime
  end
end
