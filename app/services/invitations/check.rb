module Invitations
  # Tells the invite page whether a link can still be used. It answers yes or no and nothing else: no email, no role, no inviter.
  # Unknown, malformed, expired, revoked, used (and email already taken) all give the same INVALID_INVITATION, like `Accept`.
  class Check
    def self.call(token:)
      return Errors.failure(Errors::VALIDATION_FAILED, errors: missing_token) if token.to_s.strip.empty?
      return Errors.failure(Errors::INVALID_INVITATION) unless Invitation.find_by_token(token)&.acceptable?

      Result.success
    end

    # An empty token is "required", not "invalid" (it says nothing about any invitation).
    def self.missing_token
      ActiveModel::Errors.new(Invitation.new).tap { |errors| errors.add(:token, Errors::FIELD_REQUIRED.message) }
    end
    private_class_method :missing_token
  end
end
