require "rails_helper"

RSpec.describe "Auth operations", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:user) { create(:user, email: "person@example.test", password: "correct horse battery") }

  let(:sign_up) do
    <<~GQL
      mutation($input: SignUpInput!) {
        signUp(input: $input) { token user { id email } errors { message path code } }
      }
    GQL
  end
  let(:login) do
    <<~GQL
      mutation($input: LoginInput!) {
        login(input: $input) { token user { id email } errors { message path code } }
      }
    GQL
  end
  let(:logout) { "mutation { logout(input: {}) { success errors { message path code } } }" }
  let(:me) { "{ me { id email } }" }

  def login_with(email: "person@example.test", password: "correct horse battery")
    gql(login, variables: { input: { email:, password: } })
  end

  def unauthenticated?(body)
    body["errors"]&.first&.dig("extensions", "code") == "UNAUTHENTICATED"
  end

  describe "signUp" do
    let(:input) { { email: "new@example.test", password: "correct horse battery" } }

    it "creates the user, returns a token, and allowlists it" do
      expect { gql(sign_up, variables: { input: }) }
        .to change(User, :count).by(1).and change(AllowlistedJwt, :count).by(1)

      payload = response.parsed_body.dig("data", "signUp")
      expect(response).to have_http_status(:ok)
      expect(payload["token"]).to be_present
      expect(payload["user"]).to eq("id" => User.find_by!(email: "new@example.test").id, "email" => "new@example.test")
      expect(payload["errors"]).to eq([])
    end

    it "gives a token that works" do
      token = gql(sign_up, variables: { input: })["data"]["signUp"]["token"]

      expect(gql(me, token:).dig("data", "me", "email")).to eq("new@example.test")
    end

    it "never returns the password or its hash" do
      gql(sign_up, variables: { input: })

      expect(response.body).not_to include("correct horse battery", "encrypted_password")
    end

    it "returns VALIDATION_FAILED and no token for invalid input" do
      expect { gql(sign_up, variables: { input: { email: "not-an-email", password: "x" } }) }
        .not_to change(User, :count)

      payload = response.parsed_body.dig("data", "signUp")
      expect(payload["token"]).to be_nil
      expect(payload["user"]).to be_nil
      expect(payload["errors"]).to include(a_hash_including("code" => "VALIDATION_FAILED", "path" => [ "input", "email" ]))
      expect(payload["errors"]).to include(a_hash_including("code" => "VALIDATION_FAILED", "path" => [ "input", "password" ]))
    end

    it "rejects an email that is already taken, without a token" do
      create(:user, email: "new@example.test")

      expect { gql(sign_up, variables: { input: }) }.not_to change(User, :count)
      expect(response.parsed_body.dig("data", "signUp", "token")).to be_nil
      expect(response.parsed_body.dig("data", "signUp", "errors", 0, "code")).to eq("VALIDATION_FAILED")
    end

    it "does not need a token" do
      gql(sign_up, variables: { input: }, token: "garbage")

      expect(response.parsed_body.dig("data", "signUp", "errors")).to eq([])
    end
  end

  describe "login" do
    it "returns the user and a token, and allowlists it" do
      expect { login_with }.to change { user.allowlisted_jwts.count }.by(1)

      payload = response.parsed_body.dig("data", "login")
      expect(payload["token"]).to be_present
      expect(payload["user"]).to eq("id" => user.id, "email" => "person@example.test")
      expect(payload["errors"]).to eq([])
    end

    it "accepts the email in another case" do
      body = login_with(email: "PERSON@Example.test")

      expect(body.dig("data", "login", "token")).to be_present
    end

    it "gives a different token for each login" do
      first = login_with.dig("data", "login", "token")

      expect(login_with.dig("data", "login", "token")).not_to eq(first)
    end

    it "gives the same answer for a wrong password and an unknown email" do
      wrong_password = login_with(password: "wrong password")
      unknown_email = login_with(email: "nobody@example.test")

      expect(wrong_password).to eq(unknown_email)
      expect(wrong_password.dig("data", "login")).to eq(
        "token" => nil,
        "user" => nil,
        "errors" => [ { "message" => "Invalid email or password", "path" => [ "input" ], "code" => "INVALID_CREDENTIALS" } ]
      )
    end

    it "allowlists nothing on failure" do
      expect { login_with(password: "wrong password") }.not_to change(AllowlistedJwt, :count)
    end
  end

  describe "me (token checks)" do
    it "returns the user for a valid token" do
      body = gql(me, token: token_for(user))

      expect(body.dig("data", "me")).to eq("id" => user.id, "email" => "person@example.test")
    end

    it "answers UNAUTHENTICATED without a token" do
      expect(unauthenticated?(gql(me))).to be(true)
    end

    it "answers UNAUTHENTICATED for a garbage token" do
      expect(unauthenticated?(gql(me, token: "not.a.token"))).to be(true)
    end

    it "answers UNAUTHENTICATED for a token signed with another key" do
      forged = JWT.encode({ sub: user.id.to_s, scp: "user", jti: "x", exp: 1.hour.from_now.to_i }, "other key", "HS256")

      expect(unauthenticated?(gql(me, token: forged))).to be(true)
    end

    it "answers UNAUTHENTICATED for an expired token" do
      token = token_for(user)
      travel 2.hours

      expect(unauthenticated?(gql(me, token:))).to be(true)
    end

    it "answers UNAUTHENTICATED for a token issued before a password change" do
      token = token_for(user)
      user.update!(password: "another long password")

      expect(unauthenticated?(gql(me, token:))).to be(true)
    end

    it "answers UNAUTHENTICATED, exactly like a garbage token, for the token of a locked account" do
      token = token_for(user)
      5.times { login_with(password: "wrong password 1") }
      expect(user.reload.access_locked?).to be(true)

      locked = gql(me, token:)

      expect(response).to have_http_status(:ok)
      expect(unauthenticated?(locked)).to be(true)
      expect(locked).to eq(gql(me, token: "not.a.token"))
      expect(response.body).not_to match(/lock/i)
    end

    it "accepts the token again after the account unlocks" do
      token = token_for(user)
      5.times { login_with(password: "wrong password 1") }
      user.reload.unlock_access!

      expect(gql(me, token:).dig("data", "me", "id")).to eq(user.id)
    end

    it "answers UNAUTHENTICATED for a token whose allowlist row is gone" do
      token = token_for(user)
      user.allowlisted_jwts.delete_all

      expect(unauthenticated?(gql(me, token:))).to be(true)
    end
  end

  describe "logout" do
    it "revokes the token: it works before and fails after" do
      token = token_for(user)
      expect(gql(me, token:).dig("data", "me", "email")).to eq("person@example.test")

      expect { gql(logout, token:) }.to change { user.allowlisted_jwts.count }.by(-1)
      expect(response.parsed_body.dig("data", "logout")).to eq("success" => true, "errors" => [])

      expect(unauthenticated?(gql(me, token:))).to be(true)
    end

    it "keeps the user's other tokens" do
      token = token_for(user)
      other = token_for(user)
      gql(logout, token:)

      expect(gql(me, token: other).dig("data", "me", "email")).to eq("person@example.test")
    end

    it "answers UNAUTHENTICATED when the token was already used to log out" do
      token = token_for(user)
      gql(logout, token:)

      expect(unauthenticated?(gql(logout, token:))).to be(true)
    end

    it "answers UNAUTHENTICATED without a token" do
      body = gql(logout)

      expect(unauthenticated?(body)).to be(true)
      expect(body["data"]["logout"]).to be_nil
    end
  end

  describe "unknown errors" do
    it "never reach the client" do
      allow(Auth::Login).to receive(:call).and_raise(StandardError, "secret detail from inside")

      body = login_with

      expect(response.body).not_to include("secret detail")
      expect(body["errors"].first).to include("message" => "Something went wrong", "extensions" => { "code" => "INTERNAL_ERROR" })
    end
  end

  describe "lockout" do
    def invalid_credentials?(body)
      body.dig("data", "login", "errors", 0, "code") == "INVALID_CREDENTIALS" && body.dig("data", "login", "token").nil?
    end

    it "locks the account after 5 wrong passwords, even for the right password" do
      5.times { login_with(password: "wrong password 1") }

      body = login_with

      expect(invalid_credentials?(body)).to be(true)
    end

    it "answers a locked account exactly like a wrong password and an unknown email" do
      5.times { login_with(password: "wrong password 1") }
      locked = login_with
      wrong = login_with(email: create(:user).email, password: "wrong password 1")
      unknown = login_with(email: "nobody@example.test", password: "wrong password 1")

      expect([ locked, wrong, unknown ].uniq.size).to eq(1)
    end

    it "unlocks after an hour" do
      5.times { login_with(password: "wrong password 1") }

      travel 61.minutes

      expect(login_with.dig("data", "login", "token")).to be_present
    end

    it "does not lock early, and a good login resets the counter" do
      4.times { login_with(password: "wrong password 1") }
      expect(login_with.dig("data", "login", "token")).to be_present

      4.times { login_with(password: "wrong password 1") }

      expect(login_with.dig("data", "login", "token")).to be_present
    end
  end

  describe "token storage" do
    it "removes expired allowlist rows of the user when a new token is issued" do
      user.allowlisted_jwts.create!(jti: "old", exp: 1.minute.ago)
      user.allowlisted_jwts.create!(jti: "live", exp: 1.hour.from_now)

      Auth::IssueToken.call(user)

      expect(user.allowlisted_jwts.pluck(:jti)).not_to include("old")
      expect(user.allowlisted_jwts.pluck(:jti)).to include("live")
    end
  end
end
