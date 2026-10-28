class ValidateUsersRoleCheck < ActiveRecord::Migration[8.1]
  def up
    validate_check_constraint :users, name: "users_role_values"
  end

  # A validated constraint stays enforced when rolled back. The previous migration drops it.
  def down
  end
end
