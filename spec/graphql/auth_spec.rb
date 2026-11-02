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
  let(:logout) { "mutation { logout(input: {}) { success errors { message path code } } }" }
  let(:me) { "{ me { id email } }" }

  # Step 1 only: checks the password and emails the code.
  def login_with(email: "person@example.test", password: "correct horse battery")
    request_login_code(email:, password:)
  end

  # Both steps. The answer of step 2, or of step 1 when it sent no code.
  def full_login(email: "person@example.test", password: "correct horse battery")
    log_in(email:, password:)
  end

  def code_for_person = login_code_from_email

  def invalid_code?(body)
    body.dig("data", "verifyLoginCode", "errors", 0, "code") == "INVALID_CODE" && body.dig("data", "verifyLoginCode", "token").nil?
  end

  def unauthenticated?(body)
    body["errors"]&.first&.dig("extensions", "code") == "UNAUTHENTICATED"
  end

  describe "signUp", :public_sign_up do
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

  describe "login (step 1)" do
    before { ActionMailer::Base.deliveries.clear }

    it "emails a code and returns success, without a token" do
      expect { login_with }.to change { ActionMailer::Base.deliveries.size }.by(1)

      expect(response.parsed_body.dig("data", "login")).to eq("success" => true, "errors" => [])
      expect(ActionMailer::Base.deliveries.last.to).to eq([ user.email ])
      expect(code_for_person).to match(/\A\d{6}\z/)
    end

    it "allowlists no token and keeps the code out of the response" do
      expect { login_with }.not_to change(AllowlistedJwt, :count)

      expect(response.body).not_to include(code_for_person)
    end

    it "accepts the email in another case" do
      body = login_with(email: "PERSON@Example.test")

      expect(body.dig("data", "login", "success")).to be(true)
    end

    it "gives the same answer for a wrong password and an unknown email, and sends nothing" do
      wrong_password = login_with(password: "wrong password")
      unknown_email = login_with(email: "nobody@example.test")

      expect(wrong_password).to eq(unknown_email)
      expect(wrong_password.dig("data", "login")).to eq(
        "success" => false,
        "errors" => [ { "message" => "Invalid email or password", "path" => [ "input" ], "code" => "INVALID_CREDENTIALS" } ]
      )
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "does not need a token and ignores a garbage one" do
      gql(LoginHelpers::LOGIN, variables: { input: { email: "person@example.test", password: "correct horse battery" } }, token: "garbage")

      expect(response.parsed_body.dig("data", "login", "success")).to be(true)
    end

    it "has no token or user field any more" do
      expect(Mutations::Auth::Login.fields.keys).to match_array(%w[success errors clientMutationId])
    end
  end

  describe "verifyLoginCode (step 2)" do
    before do
      ActionMailer::Base.deliveries.clear
      login_with
    end

    it "returns the user and a token, and allowlists it" do
      expect { verify_login_code(email: "person@example.test", code: code_for_person) }.to change { user.allowlisted_jwts.count }.by(1)

      payload = response.parsed_body.dig("data", "verifyLoginCode")
      expect(payload["token"]).to be_present
      expect(payload["user"]).to include("id" => user.id, "email" => "person@example.test")
      expect(payload["errors"]).to eq([])
    end

    it "gives a token that works" do
      token = verify_login_code(email: "person@example.test", code: code_for_person).dig("data", "verifyLoginCode", "token")

      expect(gql(me, token:).dig("data", "me", "email")).to eq("person@example.test")
    end

    it "accepts the email in another case" do
      body = verify_login_code(email: "PERSON@Example.test", code: code_for_person)

      expect(body.dig("data", "verifyLoginCode", "token")).to be_present
    end

    it "works once: the same code is INVALID_CODE the second time" do
      code = code_for_person
      verify_login_code(email: "person@example.test", code:)

      expect(invalid_code?(verify_login_code(email: "person@example.test", code:))).to be(true)
      expect(OneTimeCode.where(user_id: user.id)).to be_empty
    end

    it "gives a different token for each login" do
      first = verify_login_code(email: "person@example.test", code: code_for_person).dig("data", "verifyLoginCode", "token")
      second = full_login.dig("data", "verifyLoginCode", "token")

      expect(second).to be_present
      expect(second).not_to eq(first)
    end

    it "answers a wrong code, an unknown email, and a bad format with the same INVALID_CODE" do
      answers = [ verify_login_code(email: "person@example.test", code: wrong_login_code(code_for_person)),
                  verify_login_code(email: "nobody@example.test", code: code_for_person),
                  verify_login_code(email: "person@example.test", code: "12ab56"),
                  verify_login_code(email: "person@example.test", code: "") ]

      expect(answers.uniq.size).to eq(1)
      expect(invalid_code?(answers.first)).to be(true)
      expect(answers.first.dig("data", "verifyLoginCode", "errors")).to eq(
        [ { "message" => "This code is invalid or has expired", "path" => [ "input" ], "code" => "INVALID_CODE" } ]
      )
    end

    it "accepts a code just inside 10 minutes" do
      code = code_for_person
      travel 9.minutes + 59.seconds

      expect(verify_login_code(email: "person@example.test", code:).dig("data", "verifyLoginCode", "token")).to be_present
    end

    it "refuses an expired code" do
      code = code_for_person
      travel 10.minutes + 1.second

      expect(invalid_code?(verify_login_code(email: "person@example.test", code:))).to be(true)
    end

    it "deletes the code after 5 wrong guesses, so even the right code fails" do
      code = code_for_person
      5.times { verify_login_code(email: "person@example.test", code: wrong_login_code(code)) }

      expect(OneTimeCode.where(user_id: user.id)).to be_empty
      expect(invalid_code?(verify_login_code(email: "person@example.test", code:))).to be(true)
    end

    it "does not accept a code made for another purpose" do
      reset_code = Auth::IssueOneTimeCode.call(user:, purpose: :password_reset).value

      expect(invalid_code?(verify_login_code(email: "person@example.test", code: reset_code))).to be(true)
    end

    it "does not accept the code of another user" do
      other = create(:user, email: "other@example.test", password: "correct horse battery")
      login_with(email: other.email)
      other_code = login_code_from_email # the last login mail is the one of the other user

      expect(invalid_code?(verify_login_code(email: "person@example.test", code: other_code))).to be(true)
      expect(verify_login_code(email: other.email, code: other_code).dig("data", "verifyLoginCode", "token")).to be_present
    end

    it "gives no token to an account that was locked between the two steps" do
      code = code_for_person
      user.lock_access!

      expect(invalid_code?(verify_login_code(email: "person@example.test", code:))).to be(true)
      expect(OneTimeCode.where(user_id: user.id).count).to eq(1)
    end

    it "does not need a token and ignores a garbage one" do
      gql(LoginHelpers::VERIFY_LOGIN_CODE, variables: { input: { email: "person@example.test", code: code_for_person } }, token: "garbage")

      expect(response.parsed_body.dig("data", "verifyLoginCode", "token")).to be_present
    end

    it "allowlists nothing on failure" do
      expect { verify_login_code(email: "person@example.test", code: wrong_login_code(code_for_person)) }.not_to change(AllowlistedJwt, :count)
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
      travel 8.days

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
      expect(body["data"]).to be_nil
    end
  end

  describe "unknown errors" do
    it "never reach the client" do
      allow(Auth::Login).to receive(:call).and_raise(StandardError, "secret detail from inside")
      allow(Auth::VerifyLogin).to receive(:call).and_raise(StandardError, "secret detail from inside")

      bodies = [ login_with, verify_login_code(email: "person@example.test", code: "123456") ]

      expect(response.body).not_to include("secret detail")
      expect(bodies.map { |body| body["errors"].first }).to all(include("message" => "Something went wrong", "extensions" => { "code" => "INTERNAL_ERROR" }))
    end
  end

  describe "lockout" do
    def invalid_credentials?(body)
      body.dig("data", "login", "errors", 0, "code") == "INVALID_CREDENTIALS" && body.dig("data", "login", "success") == false
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

      expect(full_login.dig("data", "verifyLoginCode", "token")).to be_present
    end

    it "does not lock early, and a finished login resets the counter" do
      4.times { login_with(password: "wrong password 1") }
      expect(full_login.dig("data", "verifyLoginCode", "token")).to be_present

      4.times { login_with(password: "wrong password 1") }

      expect(login_with.dig("data", "login", "success")).to be(true)
    end

    it "keeps the failed passwords counted when the right password is typed but no code is used" do
      4.times { login_with(password: "wrong password 1") }
      login_with

      expect(user.reload.failed_attempts).to eq(4)
    end

    it "does not count wrong guesses until the code is used up" do
      login_with
      code = code_for_person
      (OneTimeCode::MAX_ATTEMPTS - 1).times { verify_login_code(email: "person@example.test", code: wrong_login_code(code)) }

      expect(user.reload.failed_attempts).to eq(0)
    end

    it "counts a used-up code as one failed login, and 5 of them lock the account" do
      Devise.maximum_attempts.times do
        login_with
        code = code_for_person
        OneTimeCode::MAX_ATTEMPTS.times { verify_login_code(email: "person@example.test", code: wrong_login_code(code)) }
      end

      expect(user.reload.access_locked?).to be(true)
      expect(invalid_credentials?(login_with)).to be(true)
    end

    it "does not let a caller who has no password count anything" do
      Devise.maximum_attempts.times { verify_login_code(email: "person@example.test", code: "123456") }

      expect(user.reload.failed_attempts).to eq(0)
      expect(user.access_locked?).to be(false)
    end

    it "answers a locked account at step 2 with INVALID_CODE" do
      login_with
      code = code_for_person
      user.lock_access!

      expect(invalid_code?(verify_login_code(email: "person@example.test", code:))).to be(true)
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
