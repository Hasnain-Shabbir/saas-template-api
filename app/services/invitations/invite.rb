module Invitations
  class Invite
    # Invites an email address. For a well-formed email it always succeeds and always enqueues one job, so the answer
    # (and the work in the request) never shows whether an account already has that email. Such an email gets no row and no mail.
    # Inviting an email that already has an open invitation updates its role and lets the job send a fresh link.
    def self.call(email:, role:, inviter:)
      invalid = Auth::RequestPasswordReset.invalid_email(email)
      return Errors.failure(Errors::VALIDATION_FAILED, errors: invalid) if invalid

      normalized = User.normalize_value_for(:email, email)
      invitation = open_invitation(email: normalized, role:, inviter:) unless User.exists?(email: normalized)

      # The job gets the id only. It makes the token itself, so the token never travels through Redis or a log.
      SendInvitationJob.perform_later(invitation&.id)
      Result.success
    end

    def self.open_invitation(email:, role:, inviter:)
      Invitation.transaction(requires_new: true) do
        invitation = Invitation.open.lock.find_by(email:)
        if invitation
          invitation.update!(role:, inviter:)
          invitation
        else
          Invitation.create!(email:, role:, inviter:, expires_at: Invitation::LIFETIME.from_now)
        end
      end
    rescue ActiveRecord::RecordNotUnique
      nil # two invites for the same email at the same moment: the unique index lets one in, and its job sends the mail
    end
    private_class_method :open_invitation
  end
end
