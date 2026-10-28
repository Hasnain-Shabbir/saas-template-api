module Auth
  # Deletes the token's allowlist row. The caller passes a token that Warden already verified;
  # the decode below is the library's verifying decoder, not a hand-written one.
  class Logout
    def self.call(user:, token:)
      payload = Warden::JWTAuth::TokenDecoder.new.call(token)
      User.revoke_jwt(payload, user)
      Result.success
    end
  end
end
