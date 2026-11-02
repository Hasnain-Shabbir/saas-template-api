# One-time codes get a third purpose, `login` (the email code of the second login step).
# The CHECK is replaced, NOT VALID first (every old row already fits the new list); the next migration validates it.
class AddLoginToOneTimeCodesPurposeCheck < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :one_time_codes, name: "one_time_codes_purpose_check"
    add_check_constraint :one_time_codes, "purpose IN ('password_reset', 'email_change', 'login')", name: "one_time_codes_purpose_check", validate: false
  end

  # A login code lives 10 minutes at most, so deleting them is the safe way back to the old list.
  def down
    execute "DELETE FROM one_time_codes WHERE purpose = 'login'"
    remove_check_constraint :one_time_codes, name: "one_time_codes_purpose_check"
    add_check_constraint :one_time_codes, "purpose IN ('password_reset', 'email_change')", name: "one_time_codes_purpose_check"
  end
end
