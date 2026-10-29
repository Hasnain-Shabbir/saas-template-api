class AddProfileToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :first_name, :string
    add_column :users, :last_name, :string
    # Encrypted by the model (`encrypts`): these columns hold ciphertext, not a date or a number, so they are text without a limit.
    # The length of their plain value is checked by the model (ValidationRules).
    add_column :users, :date_of_birth, :text
    add_column :users, :phone, :text

    # Added NOT VALID, validated in the next migration (the users table already has data). Keep in step with ValidationRules::NAME_MAX_LENGTH.
    add_check_constraint :users, "first_name IS NULL OR char_length(first_name) BETWEEN 1 AND 100", name: "users_first_name_length", validate: false
    add_check_constraint :users, "last_name IS NULL OR char_length(last_name) BETWEEN 1 AND 100", name: "users_last_name_length", validate: false
  end
end
