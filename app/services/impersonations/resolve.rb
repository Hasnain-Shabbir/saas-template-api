module Impersonations
  # Tells whether a request that the library already authenticated (signature, expiry, allowlist) is an impersonation session.
  # Success with `nil`: a normal login token. Success with a session: the token belongs to that session, the session is open and not
  # out of time, `user` is its target, and the admin behind it is still an active super_admin. Anything else is `UNAUTHENTICATED`:
  # a token whose session row says "ended" must never be taken for a plain login of the member, so it fails closed.
  # The jti comes from the library's verifying decoder, never from a hand-written decode.
  class Resolve
    def self.call(user:, token:)
      payload = Warden::JWTAuth::TokenDecoder.new.call(token)
      session = Impersonation.includes(:impersonator).find_by(jti: payload["jti"])
      return Result.success(nil) unless session

      usable?(session, user) ? Result.success(session) : Errors.failure(Errors::UNAUTHENTICATED)
    rescue JWT::DecodeError
      Errors.failure(Errors::UNAUTHENTICATED)
    end

    def self.usable?(session, user)
      admin = session.impersonator
      session.active? && session.target_id == user.id && admin.super_admin? && admin.active_for_authentication?
    end
    private_class_method :usable?
  end
end
