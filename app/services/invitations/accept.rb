module Invitations
  class Accept
    # Turns an invitation into a user. The token is the proof. Every reason it cannot work (unknown, expired, used,
    # revoked, email already taken) gives the same INVALID_INVITATION. The role comes from the invitation, never from the caller.
    def self.call(token:, password:)
      missing = missing_fields(token:, password:)
      return Errors.failure(Errors::VALIDATION_FAILED, errors: missing) if missing

      return invalid unless token.to_s.match?(ValidationRules::INVITATION_TOKEN_FORMAT)

      Invitation.transaction do
        invitation = Invitation.lock.find_by(token_digest: Invitation.digest(token))
        next invalid unless invitation&.usable?
        next invalid if User.exists?(email: invitation.email) # say nothing about the existing account

        user = User.new(email: invitation.email, password:, role: invitation.role)
        # A weak password does not use the invitation up, so the invitee can try again.
        next Errors.failure(Errors::VALIDATION_FAILED, errors: user.errors) unless user.save

        invitation.update!(accepted_at: Time.current, token_digest: nil)
        Result.success(user:, token: Auth::IssueToken.call(user))
      end
    rescue ActiveRecord::RecordNotUnique
      invalid # the email was taken at the same moment
    end

    def self.invalid = Errors.failure(Errors::INVALID_INVITATION)

    # An empty field is a plain "is required" (it says nothing about any invitation). Only a filled token can be "invalid".
    def self.missing_fields(token:, password:)
      errors = ActiveModel::Errors.new(User.new)
      errors.add(:invitation_token, Errors::FIELD_REQUIRED.message) if token.to_s.strip.empty?
      errors.add(:password, Errors::FIELD_REQUIRED.message) if password.to_s.empty?
      errors unless errors.empty?
    end
    private_class_method :invalid, :missing_fields
  end
end
