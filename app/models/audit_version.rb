# One row of the audit log: who changed which record, how, and when. Written by paper_trail (see `Auditable`), never by hand.
# A row is only ever added: once saved it is read-only, so the app cannot change or delete it.
class AuditVersion < ApplicationRecord
  include PaperTrail::VersionConcern

  before_validation :set_actor
  before_validation :clear_fields_of_destroy

  def readonly? = persisted? || super

  # `delete` skips the readonly check in Rails, so refuse it here.
  def delete = raise(ActiveRecord::ReadOnlyRecord, "#{self.class} is read-only")

  private

  # No actor set (console, runner, a test): say so, so a row never has an empty "who".
  def set_actor
    self.whodunnit = Audit.fallback_actor if whodunnit.blank?
  end

  # A destroy is recorded before the delete, when `saved_changes` still holds the last save. Never copy that into a destroy row.
  def clear_fields_of_destroy
    return unless event == "destroy"

    self.changed_fields = []
    self.value_changes = {}
  end
end
