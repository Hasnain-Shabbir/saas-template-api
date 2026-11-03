module Users
  # Takes the access of a user away: they cannot log in or use the API, and their open tokens and codes stop working at once.
  # Nothing is deleted and the user stays in the normal list, so `GrantAccess` can give the access back. It is separate from
  # `Archive`. The caller has already been authorized. Revoking a revoked user changes nothing and succeeds.
  class RevokeAccess
    def self.call(user:)
      return Result.success(user) if user.access_revoked?

      User.transaction do
        user.update!(access_revoked_at: Time.current)
        user.allowlisted_jwts.delete_all
        OneTimeCode.where(user:).delete_all # a pending login, reset, or email change code must not work later
      end

      Result.success(user)
    end
  end
end
