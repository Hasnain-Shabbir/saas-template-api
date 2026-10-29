module Invitations
  class Revoke
    # Cancels the open invitation for an email. The link stops working at once. Always succeeds for a well-formed
    # email, so it cannot be used to find out which emails were invited.
    def self.call(email:)
      invalid = Auth::RequestPasswordReset.invalid_email(email)
      return Errors.failure(Errors::VALIDATION_FAILED, errors: invalid) if invalid

      Invitation.transaction do
        invitation = Invitation.open.lock.find_by(email: User.normalize_value_for(:email, email))
        invitation&.update!(revoked_at: Time.current, token_digest: nil)
      end

      Result.success
    end
  end
end
