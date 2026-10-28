module Auth
  class ConfirmEmailChange
    # Moves `pending_email` to `email` when the code is right. `token` is the caller's own verified token: it stays valid,
    # every other session of the user ends. A taken address, a missing pending email, a wrong, expired, or used code
    # all give the same INVALID_CODE.
    def self.call(user:, code:, token:)
      result = change(user, code, token)
      SendEmailChangedNoticeJob.perform_later(user.id) if result.success?
      result
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # Someone took the address between our check and the update (the uniqueness validation or the unique index on users.email decides).
      Errors.failure(Errors::INVALID_CODE)
    end

    def self.change(user, code, token)
      User.transaction do
        user.lock!
        verified = VerifyOneTimeCode.call(user:, purpose: :email_change, code:)
        next verified if verified.failure?

        verified.value.destroy! # works once, whatever happens next
        new_email = user.pending_email
        next invalid if new_email.blank?

        # Taken in the meantime: drop the request and answer like a wrong code.
        next abandon(user) if User.exists?(email: new_email)

        user.update!(email: new_email, pending_email: nil, previous_email: user.email)
        user.allowlisted_jwts.where.not(jti: current_jti(token)).delete_all
        Result.success
      end
    end
    private_class_method :change

    def self.abandon(user)
      user.update!(pending_email: nil)
      invalid
    end
    private_class_method :abandon

    # Same verifying decoder as Logout, never a hand-written decode.
    def self.current_jti(token)
      Warden::JWTAuth::TokenDecoder.new.call(token)["jti"]
    end
    private_class_method :current_jti

    def self.invalid
      Errors.failure(Errors::INVALID_CODE)
    end
    private_class_method :invalid
  end
end
