module Auth
  class IssueToken
    def self.call(user)
      user.allowlisted_jwts.where(exp: ...Time.current).delete_all # expired rows are dead weight
      token, payload = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
      user.on_jwt_dispatch(token, payload)
      token
    end
  end
end
