class PasswordMailer < ApplicationMailer
  SUBJECT = "Your password reset code".freeze # never put the code in the subject: it shows in notifications

  def reset_password_code(user, code)
    @code = code
    @expires_in = OneTimeCode::LIFETIME.inspect

    mail(to: user.email, subject: SUBJECT)
  end
end
