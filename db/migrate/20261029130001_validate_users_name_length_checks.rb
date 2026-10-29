class ValidateUsersNameLengthChecks < ActiveRecord::Migration[8.1]
  def up
    validate_check_constraint :users, name: "users_first_name_length"
    validate_check_constraint :users, name: "users_last_name_length"
  end

  # A validated constraint stays enforced when rolled back. The previous migration drops them.
  def down
  end
end
