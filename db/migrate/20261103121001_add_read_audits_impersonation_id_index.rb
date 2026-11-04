# Partial index: only rows made during an impersonation are in it, so it stays small and answers "everything done in session X".
class AddReadAuditsImpersonationIdIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :read_audits, :impersonation_id, where: "impersonation_id IS NOT NULL", algorithm: :concurrently
  end
end
