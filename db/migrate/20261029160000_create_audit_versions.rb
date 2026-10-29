# The audit log (paper_trail): one row per create, update, or destroy of an audited model. Rows are only ever added.
# There is no `object` or `object_changes` column on purpose: paper_trail would fill them with old and new values of every
# column (password digests, personal data). Only field names (`changed_fields`) and an allowlist of safe values go in.
# `item_id` has no foreign key: a row must outlive the record it describes.
class CreateAuditVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_versions, id: :uuid do |t|
      t.string :item_type, null: false
      t.uuid :item_id, null: false
      t.string :event, null: false
      t.string :whodunnit, null: false # a user id, "anonymous", or "system:<label>"
      t.string :changed_fields, array: true, null: false, default: []
      t.jsonb :value_changes, null: false, default: {} # { "role" => [old, new] }, allowlisted fields only
      t.string :request_id
      t.datetime :created_at, null: false
    end

    add_index :audit_versions, [ :item_type, :item_id, :created_at ]
    add_index :audit_versions, :whodunnit
    add_index :audit_versions, :created_at

    add_check_constraint :audit_versions, "event IN ('create', 'update', 'destroy')", name: "audit_versions_event_values"
    add_check_constraint :audit_versions, "char_length(whodunnit) <= 100", name: "audit_versions_whodunnit_length"
    add_check_constraint :audit_versions, "char_length(request_id) <= 255", name: "audit_versions_request_id_length"
  end
end
