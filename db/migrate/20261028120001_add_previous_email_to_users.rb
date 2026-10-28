class AddPreviousEmailToUsers < ActiveRecord::Migration[8.1]
  def change
    # Where the "your email was changed" notice goes. Set when a change is confirmed and cleared once the notice is sent,
    # so the job needs only the user id (no address in job arguments).
    add_column :users, :previous_email, :citext
    add_check_constraint :users, "char_length(previous_email) <= 254", name: "users_previous_email_length", validate: false
  end
end
