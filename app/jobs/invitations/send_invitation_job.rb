module Invitations
  class SendInvitationJob < ApplicationJob
    queue_as :mailers

    retry_on Net::OpenTimeout, Net::ReadTimeout, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError

    # Safe to run twice: inside the resend cooldown the second run sends nothing.
    # The argument is the invitation id only. The address is read, and the token made, inside the service.
    def perform(invitation_id)
      invitation = Invitation.find_by(id: invitation_id)
      return unless invitation # an email that has an account, or no open invitation

      SendInvitation.call(invitation:)
    end
  end
end
