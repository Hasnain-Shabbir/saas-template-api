class EmailChangeMailer < ApplicationMailer
  CODE_SUBJECT = "Your email change code".freeze # never put the code in the subject: it shows in notifications
  NOTICE_SUBJECT = "Your account email was changed".freeze

  # Goes to the NEW address: the code proves the user owns it.
  def change_code(user, code)
    @code = code
    @expires_in = OneTimeCode::LIFETIME.inspect

    mail(to: user.pending_email, subject: CODE_SUBJECT)
  end

  # Goes to the OLD address. No code and no new address in it: the old mailbox may belong to someone else by now.
  def changed_notice(user)
    mail(to: user.previous_email, subject: NOTICE_SUBJECT)
  end
end
