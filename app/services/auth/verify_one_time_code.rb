module Auth
  class VerifyOneTimeCode
    # Checks a code without using it up (the caller deletes it when its action succeeds). Returns the code record.
    # An unknown user, a bad format, no code, a wrong code, and an expired code all give the same failure.
    # A wrong guess is counted, and guess number MAX_ATTEMPTS deletes the code. The row lock makes parallel guesses queue up.
    def self.call(user:, purpose:, code:)
      return invalid unless user && code.to_s.match?(ValidationRules::OTP_FORMAT)

      OneTimeCode.transaction do
        record = OneTimeCode.lock.find_by(user_id: user.id, purpose:)
        digest = OneTimeCode.digest(user_id: user.id, purpose:, code:)

        next invalid unless record
        next expire(record) if record.expired?
        next Result.success(record) if record.matches?(digest)

        record.increment!(:attempts)
        record.destroy! if record.attempts >= OneTimeCode::MAX_ATTEMPTS
        invalid
      end
    end

    def self.expire(record)
      record.destroy!
      invalid
    end
    private_class_method :expire

    def self.invalid
      Errors.failure(Errors::INVALID_CODE)
    end
    private_class_method :invalid
  end
end
