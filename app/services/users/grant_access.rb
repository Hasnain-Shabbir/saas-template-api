module Users
  # Gives the access back to a user whose access was revoked, with the same password and role. Old tokens and codes stay deleted:
  # they log in again. The caller has already been authorized. Granting to a user with access changes nothing and succeeds.
  # An archived user stays archived (`Unarchive` is a separate step).
  class GrantAccess
    def self.call(user:)
      user.update!(access_revoked_at: nil) if user.access_revoked?

      Result.success(user)
    end
  end
end
