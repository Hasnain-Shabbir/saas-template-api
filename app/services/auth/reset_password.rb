module Auth
  class ResetPassword
    def self.call(email:, code:, password:)
      User.transaction do
        user = User.find_for_database_authentication(email: email)
        verified = VerifyOneTimeCode.call(user:, purpose: :password_reset, code:)
        next verified if verified.failure?

        # A weak password does not use the code up, so the user can try again.
        next Errors.failure(Errors::VALIDATION_FAILED, errors: user.errors) unless user.update(password:)

        # Changing the password already deleted every token of the user (User#revoke_tokens).
        # A reset proves control of the mailbox, so it also lifts a lockout (documented decision).
        verified.value.destroy!
        user.unlock_access! if user.access_locked?
        Result.success
      end
    end
  end
end
