# Records create, update, and destroy of a model in the audit log (`AuditVersion`).
#
#   include Auditable
#   audited values: %i[role locked_at], ignore: %i[failed_attempts]
#
# Safe by default: only the NAMES of changed fields are stored. A field's old and new value is stored only when it is listed in
# `values:` (an allowlist). A new column is never stored by value until someone adds it there. Never list a password, token,
# code, digest, or personal field (a spec checks the lists).
module Auditable
  extend ActiveSupport::Concern

  NOT_LISTED = %w[id created_at updated_at].freeze

  class_methods do
    # `ignore:` fields do not create a row when they are the only change (noise, for example a counter).
    def audited(values: [], ignore: [])
      class_attribute :audited_value_fields, default: values.map(&:to_s).freeze

      has_paper_trail versions: { name: :audit_versions, class_name: "AuditVersion" },
                      on: %i[create update destroy], ignore: ignore,
                      meta: {
                        changed_fields: ->(record) { Auditable.changed_fields(record) },
                        value_changes: ->(record) { Auditable.value_changes(record) }
                      }
    end
  end

  def self.changed_fields(record) = record.saved_changes.keys - NOT_LISTED

  def self.value_changes(record) = record.saved_changes.slice(*record.class.audited_value_fields)
end
