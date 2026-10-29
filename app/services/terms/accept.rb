module Terms
  class Accept
    # Records that the logged-in user accepted the current terms. The client sends the version it showed, and it must be the current
    # one: the server never trusts a client that says "accepted" for text it did not show. Accepting again is a success and changes
    # nothing (the first `terms_accepted_at` stays). The user passed in is the caller's own: no id is taken.
    # Accepting also finishes the terms onboarding step, in the same transaction (see `Onboarding::Sync`).
    def self.call(user:, version:)
      return Errors.failure(Errors::VALIDATION_FAILED, errors: invalid_version(user, version)) unless version.to_s.strip == Current::VERSION

      # The row lock makes two requests of one user take turns.
      user.transaction do
        User.where(id: user.id).lock.pick(:id)
        user.update!(terms_version: Current::VERSION, terms_accepted_at: Time.current) unless user.terms_accepted?
        Onboarding::Sync.call(user:)
        Result.success(user)
      end
    end

    # An empty version is "is required". Only a filled one can be the wrong version.
    def self.invalid_version(user, version)
      errors = ActiveModel::Errors.new(user)
      errors.add(:version, version.to_s.strip.empty? ? Errors::FIELD_REQUIRED.message : Errors::TERMS_VERSION_OUTDATED.message)
      errors
    end
    private_class_method :invalid_version
  end
end
