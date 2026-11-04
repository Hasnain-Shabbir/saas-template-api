# RESTRICT: a session that has changes attached cannot be deleted. NOT VALID first, validated in the next migration.
class AddAuditVersionsImpersonationIdForeignKey < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :audit_versions, :impersonations, column: :impersonation_id, on_delete: :restrict, validate: false
  end
end
