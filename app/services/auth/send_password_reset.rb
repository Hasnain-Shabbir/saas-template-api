module Auth
  class SendPasswordReset
    # Makes a new code (the old one stops working) and emails it. Inside the resend cooldown nothing is sent.
    # An archived user gets nothing (the request still looks like a success, like an unknown email).
    def self.call(user:)
      return Result.success if user.archived?

      # One transaction on purpose: if the mail fails, the code is rolled back, so the job's retry is not
      # mistaken for a second request inside the cooldown.
      OneTimeCode.transaction do
        issued = IssueOneTimeCode.call(user:, purpose: :password_reset)
        PasswordMailer.reset_password_code(user, issued.value).deliver_now if issued.success?
      end

      Result.success
    end
  end
end
