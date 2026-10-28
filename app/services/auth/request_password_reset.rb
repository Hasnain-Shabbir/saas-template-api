module Auth
  class RequestPasswordReset
    # Rejects an empty or badly formed email (that says nothing about accounts).
    # For a well-formed email it always succeeds, so the answer never shows whether an account has it.
    def self.call(email:)
      invalid = invalid_email(email)
      return Errors.failure(Errors::VALIDATION_FAILED, errors: invalid) if invalid

      user = User.find_for_database_authentication(email: email)

      # Always enqueue, so a known and an unknown email do the same work in the request.
      # The job gets the id only (the code is made inside the job) and ignores a missing id.
      SendPasswordResetJob.perform_later(user&.id)
      Result.success
    end

    # Returns the errors for the email, or nil when it is fine. Also used by RequestEmailChange (`attribute` is the argument name).
    def self.invalid_email(email, attribute: :email)
      value = email.to_s.strip
      problem =
        if value.empty? then Errors::FIELD_REQUIRED
        elsif value.length > ValidationRules::EMAIL_MAX_LENGTH || !value.match?(ValidationRules::EMAIL_FORMAT) then Errors::FIELD_INVALID
        end
      return unless problem

      ActiveModel::Errors.new(User.new).tap { |errors| errors.add(attribute, problem.message) }
    end
  end
end
