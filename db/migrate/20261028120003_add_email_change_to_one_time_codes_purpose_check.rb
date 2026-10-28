class AddEmailChangeToOneTimeCodesPurposeCheck < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :one_time_codes, name: "one_time_codes_purpose_check"
    add_check_constraint :one_time_codes, "purpose IN ('password_reset', 'email_change')", name: "one_time_codes_purpose_check", validate: false
  end

  def down
    remove_check_constraint :one_time_codes, name: "one_time_codes_purpose_check"
    add_check_constraint :one_time_codes, "purpose IN ('password_reset')", name: "one_time_codes_purpose_check"
  end
end
