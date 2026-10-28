module Auth
  # Signs a JWT for the user and writes its allowlist row, so the token is accepted later.
  class IssueToken
    def self.call(user)
      token, payload = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
      user.on_jwt_dispatch(token, payload)
      token
    end
  end
end
