class ValidateReadAuditsImpersonationIdForeignKey < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :read_audits, column: :impersonation_id
  end
end
