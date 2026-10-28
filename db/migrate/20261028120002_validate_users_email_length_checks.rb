class ValidateUsersEmailLengthChecks < ActiveRecord::Migration[8.1]
  def up
    validate_check_constraint :users, name: "users_pending_email_length"
    validate_check_constraint :users, name: "users_previous_email_length"
  end

  # A validated constraint stays enforced when rolled back. The previous migrations drop them.
  def down
  end
end
