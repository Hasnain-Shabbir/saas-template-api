# Stands in for the user's inbox during the attack run. Only for the TEST database, in test mode.
# Usage: RAILS_ENV=test bin/rails runner otp_helper.rb ACTION EMAIL
#   mint     delete the user's code, issue a fresh one, print the plain code (the email would carry it)
#   expire   make the user's code expired
#   mail     mint a code, build the reset email and print its HTML body, a marker line, then its text body (nothing is sent)
#   attempts print the wrong-guess count of the user's code, or "nil" when there is none
#   role     print the user's role (the API does not expose it, so the database is the only witness)
abort "test database only" unless Rails.env.test?

action, email = ARGV
user = User.find_by!(email: email)

case action
when "mint"
  OneTimeCode.where(user_id: user.id).delete_all
  print Auth::IssueOneTimeCode.call(user: user, purpose: :password_reset).value
when "expire"
  OneTimeCode.where(user_id: user.id).update_all(expires_at: 1.minute.ago)
when "mail"
  OneTimeCode.where(user_id: user.id).delete_all
  code = Auth::IssueOneTimeCode.call(user: user, purpose: :password_reset).value
  mail = PasswordMailer.reset_password_code(user, code)
  print mail.html_part.body.decoded, "\n----TEXT----\n", mail.text_part.body.decoded
when "attempts"
  print OneTimeCode.find_by(user_id: user.id)&.attempts.inspect
when "role"
  print user.role
else
  abort "unknown action"
end
