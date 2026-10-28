class AddRoleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :role, :string, default: "member", null: false
    add_check_constraint :users, "role IN ('super_admin', 'member')", name: "users_role_values", validate: false
  end
end
