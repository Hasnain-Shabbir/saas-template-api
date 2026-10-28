module Auth
  class SendEmailChangeCode
    # Makes a new code (the old one stops working) and emails it to the pending address.
    # Inside the resend cooldown, or with no pending email (a taken address), nothing is sent.
    def self.call(user:)
      # One transaction on purpose: if the mail fails, the code is rolled back, so the job's retry is not
      # mistaken for a second request inside the cooldown. The user row lock takes turns with RequestEmailChange.
      OneTimeCode.transaction do
        user.lock!
        next if user.pending_email.blank?

        issued = IssueOneTimeCode.call(user:, purpose: :email_change)
        EmailChangeMailer.change_code(user, issued.value).deliver_now if issued.success?
      end

      Result.success
    end
  end
end
