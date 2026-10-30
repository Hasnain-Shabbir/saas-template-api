class ValidateReadAuditsFieldGroupValues < ActiveRecord::Migration[8.1]
  def up
    validate_check_constraint :read_audits, name: "read_audits_field_group_values"
  end

  # A validated constraint stays enforced when rolled back. The previous migration replaces it.
  def down
  end
end
