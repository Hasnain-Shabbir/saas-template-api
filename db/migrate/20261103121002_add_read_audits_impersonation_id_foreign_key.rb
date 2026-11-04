# RESTRICT: a session that has reads attached cannot be deleted. NOT VALID first, validated in the next migration.
class AddReadAuditsImpersonationIdForeignKey < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :read_audits, :impersonations, column: :impersonation_id, on_delete: :restrict, validate: false
  end
end
