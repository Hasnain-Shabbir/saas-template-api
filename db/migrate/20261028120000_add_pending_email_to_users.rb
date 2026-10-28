class AddPendingEmailToUsers < ActiveRecord::Migration[8.1]
  def change
    # The new address waiting for its code. Empty when no change is in progress. The login email stays untouched until the code is confirmed.
    add_column :users, :pending_email, :citext
    add_check_constraint :users, "char_length(pending_email) <= 254", name: "users_pending_email_length", validate: false
  end
end
