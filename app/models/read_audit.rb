# One row of the read audit log: who viewed which group of sensitive fields of which record, and when. Written by
# `Audit::RecordRead`, never by hand. It holds names and ids only, never a value.
# A row is only ever added: once saved it is read-only, so the app cannot change or delete it.
class ReadAudit < ApplicationRecord
  # How long a row is kept (HIPAA documentation rule). The purge job (Layer 2, item 6) reads this; nothing deletes rows before it exists.
  RETENTION = 6.years

  # Add a group here and in a migration that changes the `read_audits_field_group_values` CHECK constraint.
  FIELD_GROUPS = %w[date_of_birth contact address email_body].freeze

  validates :reader, :item_type, :item_id, presence: true
  validates :field_group, inclusion: { in: FIELD_GROUPS }

  def readonly? = persisted? || super

  # `delete` skips the readonly check in Rails, so refuse it here.
  def delete = raise(ActiveRecord::ReadOnlyRecord, "#{self.class} is read-only")
end
