class AddEmailLengthCheckToUsers < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :users, "char_length(email) <= 254", name: "users_email_length"
  end
end
