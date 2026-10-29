module Invitations
  class SendInvitation
    # Makes a new token (an earlier link stops working), stores only its digest, and emails the link.
    # Does nothing for an invitation that was used or revoked, or inside the resend cooldown.
    def self.call(invitation:)
      # One transaction on purpose: if the mail fails, the digest is rolled back, so the job's retry is not
      # mistaken for a second request inside the cooldown.
      Invitation.transaction do
        invitation.lock!
        next unless invitation.open? && !invitation.recently_sent?

        token = Invitation.generate_token
        invitation.update!(token_digest: Invitation.digest(token), expires_at: Invitation::LIFETIME.from_now, last_sent_at: Time.current)
        InvitationMailer.invite(invitation, token).deliver_now
      end

      Result.success
    end
  end
end
