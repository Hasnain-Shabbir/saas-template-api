module Auth
  class Login
    # Step 1 of a login: checks the password and, when it is right, queues an email with a code. No token yet: VerifyLogin gives it
    # for the code. Unknown email, wrong password, and locked account all give the same failure and run bcrypt once.
    def self.call(email:, password:)
      user = User.find_for_database_authentication(email: email)
      # Always run bcrypt, so a locked or unknown account takes as long as a real check.
      password_ok = user ? user.valid_password?(password) : dummy_check(password)

      # Only a caller who knows the password learns that the account is archived (so they can ask an administrator).
      return Errors.failure(Errors::ACCOUNT_ARCHIVED) if password_ok && user.archived?

      if user&.valid_for_authentication? { password_ok } && user.active_for_authentication?
        # The job gets the id only: the code is made inside it. The failed attempts stay counted until a code is verified.
        SendLoginCodeJob.perform_later(user.id)
        Result.success
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
