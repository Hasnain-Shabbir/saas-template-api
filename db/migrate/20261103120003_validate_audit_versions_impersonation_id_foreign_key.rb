class ValidateAuditVersionsImpersonationIdForeignKey < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :audit_versions, column: :impersonation_id
  end
end
