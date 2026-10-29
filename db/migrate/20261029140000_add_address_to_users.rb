class AddAddressToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :address_line_1, :string
    add_column :users, :address_line_2, :string
    add_column :users, :city, :string
    add_column :users, :state, :string
    add_column :users, :postal_code, :string
    add_column :users, :country, :string

    # Added NOT VALID, validated in the next migration (the users table already has data). The formats (US state, ZIP) are checked by the
    # model (ValidationRules); the database keeps only the sizes, so opening a new country later needs no migration.
    # Keep in step with ValidationRules::ADDRESS_MAX_LENGTH and POSTAL_CODE_MAX_LENGTH.
    add_check_constraint :users, "address_line_1 IS NULL OR char_length(address_line_1) BETWEEN 1 AND 100", name: "users_address_line_1_length", validate: false
    add_check_constraint :users, "address_line_2 IS NULL OR char_length(address_line_2) BETWEEN 1 AND 100", name: "users_address_line_2_length", validate: false
    add_check_constraint :users, "city IS NULL OR char_length(city) BETWEEN 1 AND 100", name: "users_city_length", validate: false
    add_check_constraint :users, "state IS NULL OR char_length(state) = 2", name: "users_state_length", validate: false
    add_check_constraint :users, "postal_code IS NULL OR char_length(postal_code) BETWEEN 1 AND 10", name: "users_postal_code_length", validate: false
    add_check_constraint :users, "country IS NULL OR char_length(country) = 2", name: "users_country_length", validate: false
  end
end
