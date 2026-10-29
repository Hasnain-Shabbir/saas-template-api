class ValidateUsersAddressLengthChecks < ActiveRecord::Migration[8.1]
  def up
    %w[address_line_1 address_line_2 city state postal_code country].each do |column|
      validate_check_constraint :users, name: "users_#{column}_length"
    end
  end

  # A validated constraint stays enforced when rolled back. The previous migration drops them.
  def down
  end
end
