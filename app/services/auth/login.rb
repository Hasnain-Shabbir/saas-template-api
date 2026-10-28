module Auth
  class Login
    def self.call(email:, password:)
      user = User.find_for_database_authentication(email: email)
      # Always run bcrypt, so a locked or unknown account takes as long as a real check.
      password_ok = user ? user.valid_password?(password) : dummy_check(password)

      if user&.valid_for_authentication? { password_ok } && user.active_for_authentication?
        user.unlock_access! if user.failed_attempts.positive? # Devise resets this in a Warden hook, which we do not use
        Result.success(user:, token: IssueToken.call(user))
      else
        Errors.failure(Errors::INVALID_CREDENTIALS)
      end
    end

    # Hashing a password costs the same as checking one. (A blank User#valid_password? skips bcrypt.)
    def self.dummy_check(password)
      User.new(password: password)
      false
    end
    private_class_method :dummy_check
  end
end
