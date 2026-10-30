FactoryBot.define do
  factory :email_log do
    recipient { "person@example.test" }
    mailer { "PasswordMailer" }
    action { "reset_password_code" }
    subject { "Your password reset code" }
    body { "Your code is: 042917" }
    status { "sent" }
    sent_at { Time.current }
  end
end
