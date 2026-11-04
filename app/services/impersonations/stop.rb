module Impersonations
  # Ends a session and kills its token at once. `ended_reason` is "stopped" when the admin ends it, or "ended_by_system" when
  # a block or a password change ends it. A session that already ran out is recorded as `expired`, ending at `expires_at`, whatever the
  # caller says: nobody ended it, the time did. Ending an ended session changes nothing and succeeds.
  class Stop
    def self.call(impersonation:, ended_reason: "stopped")
      impersonation.with_lock do
        unless impersonation.ended_at
          now = Time.current
          ran_out = impersonation.expires_at <= now
          impersonation.update!(ended_at: ran_out ? impersonation.expires_at : now, ended_reason: ran_out ? "expired" : ended_reason)
        end
        AllowlistedJwt.where(jti: impersonation.jti).delete_all
      end

      Result.success(impersonation)
    end
  end
end
