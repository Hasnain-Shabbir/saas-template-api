# The read audit log: who viewed which group of sensitive fields of which record (HIPAA "who viewed what").
# It is a separate table from `audit_versions` (changes): reads are far more frequent and are kept on their own schedule.
# No values are stored, only names: the reader, the record, and a group such as "contact". A new group needs a new migration for the CHECK.
# `item_id` has no foreign key: a row must outlive the record it describes.
class CreateReadAudits < ActiveRecord::Migration[8.1]
  def change
    create_table :read_audits, id: :uuid do |t|
      t.string :reader, null: false # a user id, or "system:<label>"
      t.string :item_type, null: false
      t.uuid :item_id, null: false
      t.string :field_group, null: false # "date_of_birth", "contact", or "address"
      t.string :request_id
      t.datetime :created_at, null: false
    end

    add_index :read_audits, [ :item_type, :item_id, :created_at ]
    add_index :read_audits, [ :reader, :created_at ]
    add_index :read_audits, :created_at

    add_check_constraint :read_audits, "field_group IN ('date_of_birth', 'contact', 'address')", name: "read_audits_field_group_values"
    add_check_constraint :read_audits, "char_length(reader) <= 100", name: "read_audits_reader_length"
    add_check_constraint :read_audits, "char_length(request_id) <= 255", name: "read_audits_request_id_length"
  end
end
