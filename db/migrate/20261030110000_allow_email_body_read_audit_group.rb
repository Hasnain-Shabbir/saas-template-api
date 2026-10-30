# The read audit log gets a new field group, `email_body`: an admin read the body of a stored email (it holds live codes and links).
# The CHECK is replaced, NOT VALID first (every old row already fits the new list); the next migration validates it.
class AllowEmailBodyReadAuditGroup < ActiveRecord::Migration[8.1]
  OLD_GROUPS = "'date_of_birth', 'contact', 'address'".freeze
  NEW_GROUPS = "#{OLD_GROUPS}, 'email_body'".freeze

  def up
    remove_check_constraint :read_audits, name: "read_audits_field_group_values"
    add_check_constraint :read_audits, "field_group IN (#{NEW_GROUPS})", name: "read_audits_field_group_values", validate: false
  end

  def down
    remove_check_constraint :read_audits, name: "read_audits_field_group_values"
    add_check_constraint :read_audits, "field_group IN (#{OLD_GROUPS})", name: "read_audits_field_group_values"
  end
end
