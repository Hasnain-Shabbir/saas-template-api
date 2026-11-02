module Auth
  class VerifyLogin
    # Step 2 of a login: the code from the email gives the token. The code works once.
    # An unknown email, a locked or archived account, no code, a wrong code, and an expired code all give the same INVALID_CODE.
    def self.call(email:, code:)
      # One transaction (like ResetPassword): the row lock on the code stays until the code is deleted, so a code cannot be used twice at once.
      User.transaction do
        user = User.find_for_database_authentication(email: email)
        # An account locked between the two steps gets no token, even with the right code.
        next invalid unless user&.active_for_authentication?

        verified = VerifyOneTimeCode.call(user:, purpose: :login, code:) { count_failed_attempt(user) }
        next verified if verified.failure?

        verified.value.destroy!
        user.unlock_access! if user.failed_attempts.positive? # Devise resets this in a Warden hook, which we do not use
        Result.success(user:, token: IssueToken.call(user))
      end
    end

    # A used-up code (5 wrong guesses) counts as one failed login, so 5 of them lock the account. Counting every wrong guess would let
    # anyone who knows an email lock that account, because this step needs no password.
    def self.count_failed_attempt(user)
      user.valid_for_authentication? { false }
    end
    private_class_method :count_failed_attempt

    def self.invalid
      Errors.failure(Errors::INVALID_CODE)
    end
    private_class_method :invalid
  end
end
