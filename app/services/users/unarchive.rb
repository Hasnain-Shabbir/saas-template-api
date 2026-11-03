module Users
  # Lets an archived user log in again, with the same password and role. Old tokens and codes stay deleted: they log in again.
  # The caller has already been authorized. Unarchiving an active user changes nothing and succeeds.
  class Unarchive
    def self.call(user:)
      user.update!(archived_at: nil) if user.archived?

      Result.success(user)
    end
  end
end
