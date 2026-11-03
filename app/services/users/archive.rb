module Users
  # Blocks a user: they cannot log in or use the API, and their open tokens and codes stop working at once. Nothing is deleted,
  # so `Unarchive` can bring them back with the same password and role. The caller has already been authorized.
  # Archiving an archived user changes nothing and succeeds.
  class Archive
    def self.call(user:)
      return Result.success(user) if user.archived?

      User.transaction do
        user.update!(archived_at: Time.current)
        user.allowlisted_jwts.delete_all
        OneTimeCode.where(user:).delete_all # a pending login, reset, or email change code must not work later
      end

      Result.success(user)
    end
  end
end
