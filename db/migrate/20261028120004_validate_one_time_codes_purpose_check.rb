class ValidateOneTimeCodesPurposeCheck < ActiveRecord::Migration[8.1]
  def up
    validate_check_constraint :one_time_codes, name: "one_time_codes_purpose_check"
  end

  # A validated constraint stays enforced when rolled back. The previous migration restores the old list.
  def down
  end
end
