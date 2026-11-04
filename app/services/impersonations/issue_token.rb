module Impersonations
  # Issues the token of an impersonation session: a normal token for `target`, but with its own short expiry and a `jti` chosen by
  # the caller (so the session row can point at it). It is signed by the library's encoder and listed in the allowlist, like a login token.
  # The expiry is a signed claim, so the library refuses the token after `expires_at` without any extra check from us.
  class IssueToken
    def self.call(target:, jti:, expires_at:)
      payload = Warden::JWTAuth::PayloadUserHelper.payload_for_user(target, :user).merge("aud" => nil, "jti" => jti, "exp" => expires_at.to_i)
      token = Warden::JWTAuth::TokenEncoder.new.call(payload)
      target.on_jwt_dispatch(token, payload)
      token
    end
  end
end
