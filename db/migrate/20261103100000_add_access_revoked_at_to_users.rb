# Layer 3, step 3: a super_admin can revoke the access of a user. A timestamp, not a boolean, because it also says when. NULL means
# access is allowed. It is separate from `archived_at`: a user can be archived, revoked, both, or neither.
class AddAccessRevokedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :access_revoked_at, :datetime
  end
end
