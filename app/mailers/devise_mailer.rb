# Devise's own mails (unlock or confirmation instructions) if they are ever turned on. Set in `config.mailer` (devise.rb).
# Today none is sent: the lockout unlocks by time, not by email. It is here so such a mail is logged like any other.
class DeviseMailer < Devise::Mailer
  include EmailLoggable
end
