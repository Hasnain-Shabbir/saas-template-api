module Auth
  class IssueOneTimeCode
    # Makes a new code for the user and purpose, and deletes the old one. Returns the code (the only time it exists
    # in plain text), or a RATE_LIMITED failure inside the resend cooldown. The caller must not show that to the client.
    def self.call(user:, purpose:)
      OneTimeCode.transaction(requires_new: true) do # a savepoint, so the rescue below leaves an outer transaction usable
        existing = OneTimeCode.lock.find_by(user_id: user.id, purpose:)
        next Errors.failure(Errors::RATE_LIMITED) if existing&.recently_sent?

        existing&.destroy!
        code = SecureRandom.random_number(10**ValidationRules::OTP_LENGTH).to_s.rjust(ValidationRules::OTP_LENGTH, "0")
        OneTimeCode.create!(
          user:, purpose:, expires_at: OneTimeCode::LIFETIME.from_now,
          code_digest: OneTimeCode.digest(user_id: user.id, purpose:, code:)
        )
        Result.success(code)
      end
    rescue ActiveRecord::RecordNotUnique
      # Two requests at the same moment: the unique index lets one create the code, the other is inside the cooldown.
      Errors.failure(Errors::RATE_LIMITED)
    end
  end
end
