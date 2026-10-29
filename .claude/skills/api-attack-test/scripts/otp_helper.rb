# Stands in for the user's inbox during the attack run. Only for the TEST database, in test mode.
# Usage: RAILS_ENV=test bin/rails runner otp_helper.rb ACTION EMAIL
#   mint     delete the user's code, issue a fresh one, print the plain code (the email would carry it)
#   expire   make the user's code expired
#   mail     mint a code, build the reset email and print its HTML body, a marker line, then its text body (nothing is sent)
#   attempts print the wrong-guess count of the user's password reset code, or "nil" when there is none
#   role     print the user's role (the API does not expose it, so the database is the only witness)
#   ec_mint  EMAIL NEW_EMAIL  set the pending email, issue an email_change code, print the plain code (the new inbox)
#   ec_expire  make the user's email_change code expired
#   ec_state print JSON: email, pending, previous, code present, attempts, locked, failed attempts, token count
#   ec_mail  EMAIL NEW_EMAIL  like ec_mint, but print the code mail (html, marker line, text) instead of the code
#   make_admin    make the user a super_admin (the API has no way to do that, on purpose)
#   inv_mint EMAIL ROLE  create an open invitation for EMAIL and print its plain token (the invitee's inbox). Test mode only:
#                        production mode has another secret key, so its digests do not match
#   inv_expire    make the open invitation of EMAIL expired
#   terms_version print the version of the terms the server accepts now (EMAIL is ignored)
#   profile_raw   print JSON: the stored (raw) first name, last name, date of birth and phone of EMAIL, as the database holds them
#   audit_dump    print every audit log row as JSON text (EMAIL is ignored); the attack run searches it for secrets
#   audit_write   try to change and to delete an audit row, print "blocked" when the app refuses both
#   inv_state     print JSON: invitations of EMAIL (role, accepted, revoked, digest present), and whether a user exists
abort "test database only" unless Rails.env.test?

action, email = ARGV

if action == "terms_version"
  print Terms::Current::VERSION
  exit
end

if action == "audit_dump"
  print JSON.generate(AuditVersion.all.map(&:attributes))
  exit
end

if action == "audit_write"
  row = AuditVersion.first
  refused = [ -> { row.update!(whodunnit: "forged") }, -> { row.destroy! } ].all? do |change|
    change.call
    false
  rescue ActiveRecord::ReadOnlyRecord
    true
  end
  print(refused && row.reload.whodunnit != "forged" ? "blocked" : "changed")
  exit
end

if action == "profile_raw"
  row = User.connection.select_one(User.sanitize_sql([ "SELECT first_name, last_name, date_of_birth, phone FROM users WHERE email = ?", email ]))
  print JSON.generate(row || {})
  exit
end

if action.start_with?("inv_")
  case action
  when "inv_mint"
    Invitation.where(email: email).delete_all
    token = Invitation.generate_token
    Invitation.create!(email: email, role: ARGV[2] || "member", token_digest: Invitation.digest(token), expires_at: Invitation::LIFETIME.from_now, last_sent_at: Time.current)
    print token
  when "inv_expire"
    Invitation.open.where(email: email).update_all(expires_at: 1.minute.ago)
  when "inv_state"
    print JSON.generate(invitations: Invitation.where(email: email).map { |i| { role: i.role, accepted: !i.accepted_at.nil?, revoked: !i.revoked_at.nil?, digest: !i.token_digest.nil? } },
                        user: User.exists?(email: email), role: User.find_by(email: email)&.role)
  else
    abort "unknown action"
  end
  exit
end

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
  print OneTimeCode.find_by(user_id: user.id, purpose: "password_reset")&.attempts.inspect
when "role"
  print user.role
when "make_admin"
  user.update!(role: "super_admin")
when "ec_mint", "ec_mail"
  OneTimeCode.where(user_id: user.id, purpose: "email_change").delete_all
  user.update!(pending_email: ARGV[2])
  code = Auth::IssueOneTimeCode.call(user: user, purpose: :email_change).value
  if action == "ec_mint"
    print code
  else
    mail = EmailChangeMailer.change_code(user, code)
    print mail.html_part.body.decoded, "\n----TEXT----\n", mail.text_part.body.decoded
  end
when "ec_expire"
  OneTimeCode.where(user_id: user.id, purpose: "email_change").update_all(expires_at: 1.minute.ago)
when "ec_state"
  code = OneTimeCode.find_by(user_id: user.id, purpose: "email_change")
  print JSON.generate(email: user.email, pending: user.pending_email, previous: user.previous_email, code: !code.nil?,
                      attempts: code&.attempts, locked: user.access_locked?, failed: user.failed_attempts, tokens: user.allowlisted_jwts.count)
else
  abort "unknown action"
end
