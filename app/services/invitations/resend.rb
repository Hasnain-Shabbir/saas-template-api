module Invitations
  class Resend
    # Sends a fresh link for the invitation of an email (the old link stops working, the expiry restarts).
    # An open invitation is used as it is. Without one, the latest revoked invitation is reopened (same role and inviter),
    # unless the email already has an account. A used invitation is never reopened.
    # Always succeeds and enqueues one job for a well-formed email, so it never shows which emails were invited.
    # Inside the 60 second cooldown the job sends nothing.
    def self.call(email:)
      invalid = Auth::RequestPasswordReset.invalid_email(email)
      return Errors.failure(Errors::VALIDATION_FAILED, errors: invalid) if invalid

      invitation = open_or_reopen(User.normalize_value_for(:email, email))
      SendInvitationJob.perform_later(invitation&.id)
      Result.success
    end

    def self.open_or_reopen(email)
      Invitation.transaction(requires_new: true) do
        Invitation.open.find_by(email:) || reopen_revoked(email)
      end
    rescue ActiveRecord::RecordNotUnique
      nil # an invitation for this email was made at the same moment, and its own job sends the mail
    end

    def self.reopen_revoked(email)
      return if User.exists?(email:)

      invitation = Invitation.revoked.where(email:).order(revoked_at: :desc).lock.first
      # last_sent_at is cleared so the cooldown from the first send cannot block the new link (revoke removed the old digest).
      invitation&.update!(revoked_at: nil, last_sent_at: nil)
      invitation
    end
    private_class_method :open_or_reopen, :reopen_revoked
  end
end
