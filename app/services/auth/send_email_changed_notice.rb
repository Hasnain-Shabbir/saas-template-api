module Auth
  class SendEmailChangedNotice
    # Tells the old address that the email was changed, then forgets that address. Safe to run twice.
    def self.call(user:)
      user.with_lock do
        next if user.previous_email.blank?

        EmailChangeMailer.changed_notice(user).deliver_now
        user.update!(previous_email: nil)
      end

      Result.success
    end
  end
end
