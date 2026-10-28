module Auth
  class Login
    def self.call(email:, password:)
      user = User.find_for_database_authentication(email: email)

      if user&.valid_password?(password)
        Result.success(user:, token: IssueToken.call(user))
      else
        # Unknown email and wrong password look the same, in the answer and in the time taken.
        User.new(password: password) unless user # same bcrypt cost as a real check
        Errors.failure(Errors::INVALID_CREDENTIALS)
      end
    end
  end
end
