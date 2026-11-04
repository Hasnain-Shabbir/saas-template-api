module Impersonations
  # Starts a session in which `impersonator` acts as `target`. Returns the session row and a token for the target that lasts
  # `Impersonation::TTL`. The admin's own token is untouched. The caller has only checked that someone is logged in; the rules are here:
  # the impersonator is an active super_admin, the target is an active member (never a super_admin, so never the admin themself, and
  # never an archived or access-revoked user), and the category is valid (and a note is given for "other"). An admin has one open
  # session at a time, on any device: a new start ends the old one (as `ended_by_system`, or `expired` when it had run out) and kills
  # its token, so the old device is logged out of the impersonation, not of the admin's own session. A locked target is allowed (owner decision).
  # While impersonating, the logged-in user is a member, so a started session cannot start another one.
  class Start
    Started = Data.define(:impersonation, :token)

    def self.call(impersonator:, target:, reason_category:, reason: nil, request_id: nil)
      return Errors.failure(Errors::FORBIDDEN) unless impersonator.super_admin? && !impersonator.blocked?
      return Errors.failure(Errors::IMPERSONATE_SUPER_ADMIN) if target.super_admin?
      return Errors.failure(Errors::IMPERSONATE_BLOCKED_USER) if target.blocked?

      started_at = Time.current
      impersonation = Impersonation.new(impersonator:, target:, reason_category:, reason:, request_id:, jti: SecureRandom.uuid,
                                        started_at:, expires_at: started_at + Impersonation::TTL)
      return Errors.failure(Errors::VALIDATION_FAILED, errors: impersonation.errors) unless impersonation.valid?

      Impersonation.transaction do
        end_open_sessions(impersonator)
        impersonation.save!
        token = IssueToken.call(target:, jti: impersonation.jti, expires_at: impersonation.expires_at)
        Result.success(Started.new(impersonation:, token:))
      end
    rescue ActiveRecord::RecordNotUnique
      # Two starts at once: the database allows only one open session per admin.
      Errors.failure(Errors::IMPERSONATION_ACTIVE)
    end

    # `Stop` records a session that already ran out as `expired`, ending at its expiry, so the log never claims it lasted longer.
    def self.end_open_sessions(impersonator)
      Impersonation.unended.where(impersonator_id: impersonator.id).find_each do |session|
        Stop.call(impersonation: session, ended_reason: "ended_by_system")
      end
    end
    private_class_method :end_open_sessions
  end
end
