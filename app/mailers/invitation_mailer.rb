class InvitationMailer < ApplicationMailer
  SUBJECT = "You are invited to create an account".freeze
  ACCEPT_PATH = "/accept-invitation".freeze # the frontend page that calls acceptInvitation

  # The link carries the token. Never put it in the subject, and never log the mail body.
  def invite(invitation, token)
    @link = "#{Rails.configuration.x.frontend_url}#{ACCEPT_PATH}?token=#{ERB::Util.url_encode(token)}"
    @expires_in = Invitation::LIFETIME.inspect

    mail(to: invitation.email, subject: SUBJECT)
  end
end
