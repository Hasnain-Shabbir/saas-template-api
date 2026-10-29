class AddTermsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :terms_version, :string
    add_column :users, :terms_accepted_at, :datetime

    # Added NOT VALID, validated in the next migration (the users table already has data). Keep in step with ValidationRules::TERMS_VERSION_MAX_LENGTH.
    add_check_constraint :users, "terms_version IS NULL OR char_length(terms_version) BETWEEN 1 AND 20", name: "users_terms_version_length", validate: false
  end
end
