# Links a change made during an impersonation session to that session (null for every normal request). The session row says who the
# admin was and why; this column says which changes belong to it. The index and the foreign key follow in their own migrations (safe on a table with data).
class AddImpersonationIdToAuditVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :audit_versions, :impersonation_id, :uuid
  end
end
