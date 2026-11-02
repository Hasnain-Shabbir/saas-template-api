class LoginMailer < ApplicationMailer
  SUBJECT = "Your login code".freeze # never put the code in the subject: it shows in notifications

  def login_code(user, code)
    @code = code
    @expires_in = OneTimeCode::LIFETIME.inspect

    mail(to: user.email, subject: SUBJECT)
  end
end
