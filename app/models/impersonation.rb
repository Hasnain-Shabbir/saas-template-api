# One impersonation session: `impersonator` (a super_admin) acted as `target` (a member). Written by the impersonation services.
# A row is only ever added; the one allowed change is to end it, once (`ended_at` and `ended_reason`). It cannot be deleted.
# Known limit (owner decision): `update_columns` on a session that has not ended is not blocked, because only a database trigger could
# stop it, and someone with console or database access could bypass that too. The model blocks every normal write path.
# A session has no refresh. When `expires_at` passes it is over, even if `ended_at` is still empty (no job closes it).
class Impersonation < ApplicationRecord
  # How long a session lasts. The token's expiry is set from this, so the token and the log agree.
  TTL = 30.minutes
  # How long a row is kept (HIPAA documentation rule). The purge job (Layer 2, item 6) reads this; nothing deletes rows before it exists.
  RETENTION = 6.years

  ENDING_ATTRIBUTES = %w[ended_at ended_reason].freeze

  belongs_to :impersonator, class_name: "User"
  belongs_to :target, class_name: "User"

  # stopped: the admin ended it. expired: the time ran out. ended_by_system: the system ended it: the admin started a new session, the target or the admin was blocked, or the admin changed their password.
  enum :ended_reason, { stopped: "stopped", expired: "expired", ended_by_system: "ended_by_system" }, prefix: :ended_as, validate: { allow_nil: true }

  validates :jti, :started_at, :expires_at, presence: true
  # Why the session was started. The note is required for "other" and optional for the rest. A new category needs a migration for the CHECK.
  enum :reason_category, {
    support_request: "support_request", bug_investigation: "bug_investigation", data_correction: "data_correction",
    security_investigation: "security_investigation", other: "other"
  }, prefix: :reason, validate: true

  normalizes :reason, with: ->(reason) { reason.strip.presence }

  validates :reason_category, presence: true
  validates :reason, presence: true, if: :reason_other?
  validates :reason, length: { maximum: ValidationRules::IMPERSONATION_REASON_MAX_LENGTH }
  validate :not_self

  before_update :only_ending_may_change

  scope :unended, -> { where(ended_at: nil) }

  # True while the session can still be used: not ended and not out of time.
  def active?(now = Time.current)
    ended_at.nil? && expires_at > now
  end

  # When the session really ended: the moment it was ended, or else the moment it ran out.
  def effective_end
    ended_at || expires_at
  end

  # An ended row can no longer change at all.
  def readonly? = (persisted? && ended_at_in_database.present?) || super

  # `delete` skips the readonly check in Rails, and `destroy` is refused here too.
  def delete = raise(ActiveRecord::ReadOnlyRecord, "#{self.class} is read-only")

  def destroy = raise(ActiveRecord::ReadOnlyRecord, "#{self.class} is read-only")

  private

  def not_self
    errors.add(:target, "cannot be the impersonator") if impersonator_id.present? && impersonator_id == target_id
  end

  # Anything but ending the session is refused, so the "who, whom, why, when" of a row never changes.
  def only_ending_may_change
    return if (changed - ENDING_ATTRIBUTES).empty?

    raise ActiveRecord::ReadOnlyRecord, "#{self.class} can only be ended, not edited"
  end
end
