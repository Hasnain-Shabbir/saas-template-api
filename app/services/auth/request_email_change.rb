module Auth
  class RequestEmailChange
    # Starts an email change for the logged-in user. The password must be right (a stolen token alone is not enough).
    # For a well-formed email it always succeeds, so the answer never shows whether another account has that email.
    # The login email does not change here: the new one waits in `pending_email` until the code is confirmed.
    def self.call(user:, new_email:, password:)
      # The format check comes first: it says nothing about accounts, and the user sees a bad email before a password problem.
      invalid = RequestPasswordReset.invalid_email(new_email, attribute: :new_email)
      return Errors.failure(Errors::VALIDATION_FAILED, errors: invalid) if invalid

      return Errors.failure(Errors::INVALID_CREDENTIALS) unless password_ok?(user, password)

      store_pending_email(user, User.normalize_value_for(:email, new_email))

      # Always enqueue, so a free and a taken email do the same work in the request. The job sends nothing without a pending email.
      SendEmailChangeCodeJob.perform_later(user.id)
      Result.success
    end

    # Counts a wrong password like a failed login (Devise lockable), so a stolen token cannot guess the password without limit.
    def self.password_ok?(user, password)
      ok = user.valid_for_authentication? { user.valid_password?(password) }
      user.unlock_access! if ok && user.failed_attempts.positive?
      ok
    end
    private_class_method :password_ok?

    # The row lock makes this and the job (SendEmailChangeCode) take turns, so a code is never sent to one address
    # while `pending_email` already holds another. Inside the resend cooldown the earlier request stays as it is.
    def self.store_pending_email(user, email)
      user.with_lock do
        next if OneTimeCode.find_by(user_id: user.id, purpose: :email_change)&.recently_sent?

        # Taken (by anyone, this user included): nothing is kept, so nothing is sent.
        if User.exists?(email:)
          OneTimeCode.where(user_id: user.id, purpose: :email_change).delete_all
          user.update!(pending_email: nil)
        else
          user.update!(pending_email: email)
        end
      end
    end
    private_class_method :store_pending_email
  end
end
