require "rails_helper"

RSpec.describe "Password reset", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let!(:user) { create(:user, email: "person@example.test", password: "correct horse battery") }
  let(:new_password) { "a brand new password" }

  let(:request_reset) do
    <<~GQL
      mutation($input: RequestPasswordResetInput!) {
        requestPasswordReset(input: $input) { success errors { message path code } }
      }
    GQL
  end
  let(:reset_password) do
    <<~GQL
      mutation($input: ResetPasswordInput!) {
        resetPassword(input: $input) { success errors { message path code } }
      }
    GQL
  end
  let(:login) do
    <<~GQL
      mutation($input: LoginInput!) {
        login(input: $input) { token errors { message path code } }
      }
    GQL
  end
  let(:me) { "{ me { id email } }" }

  before { ActionMailer::Base.deliveries.clear }

  def ask_for_reset(email = "person@example.test")
    perform_enqueued_jobs { gql(request_reset, variables: { input: { email: } }) }
  end

  # The code only exists in the email (the database keeps a digest), so the tests read it from there, like a user would.
  def code_from_email
    ActionMailer::Base.deliveries.last.text_part.body.decoded[/^(\d{6})$/, 1]
  end

  def reset_with(code, email: "person@example.test", password: new_password)
    gql(reset_password, variables: { input: { email:, code:, password: } })
  end

  def wrong_code
    code_from_email == "000000" ? "111111" : "000000"
  end

  def login_with(password)
    gql(login, variables: { input: { email: "person@example.test", password: } }).dig("data", "login", "token")
  end

  def invalid_code?(body)
    body.dig("data", "resetPassword", "errors", 0, "code") == "INVALID_CODE" && body.dig("data", "resetPassword", "success") == false
  end

  describe "requestPasswordReset" do
    it "emails a 6-digit code to a known email" do
      ask_for_reset

      mail = ActionMailer::Base.deliveries.last
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(mail.to).to eq([ "person@example.test" ])
      expect(mail.from).to eq([ Rails.configuration.x.mailer_from ])
      expect(code_from_email).to match(ValidationRules::OTP_FORMAT)
      expect(mail.html_part.body.decoded).to include(code_from_email)
    end

    it "keeps the code out of the subject" do
      ask_for_reset

      expect(ActionMailer::Base.deliveries.last.subject).not_to match(/\d{6}/)
    end

    it "answers exactly the same for a known and an unknown email" do
      known = ask_for_reset
      unknown = ask_for_reset("nobody@example.test")

      expect(known).to eq(unknown)
      expect(known.dig("data", "requestPasswordReset")).to eq("success" => true, "errors" => [])
    end

    it "sends nothing for an unknown email" do
      body = ask_for_reset("nobody@example.test")

      expect(body.dig("data", "requestPasswordReset")).to eq("success" => true, "errors" => [])
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "asks for an email when it is empty or blank" do
      [ "", "   " ].each do |email|
        payload = ask_for_reset(email).dig("data", "requestPasswordReset")

        expect(payload["success"]).to be(false)
        expect(payload["errors"]).to eq([ { "message" => "Email is required", "path" => %w[input email], "code" => "VALIDATION_FAILED" } ])
      end
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "rejects text that is not a valid email" do
      [ "123124", "not-an-email", "a@b", "#{'a' * ValidationRules::EMAIL_MAX_LENGTH}@example.test" ].each do |email|
        payload = ask_for_reset(email).dig("data", "requestPasswordReset")

        expect(payload["success"]).to be(false)
        expect(payload["errors"]).to eq([ { "message" => "Email is invalid", "path" => %w[input email], "code" => "VALIDATION_FAILED" } ])
      end
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "accepts the email in another case" do
      ask_for_reset("PERSON@Example.test")

      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it "enqueues a job with the user id only, and does the same for an unknown email" do
      expect { gql(request_reset, variables: { input: { email: "person@example.test" } }) }
        .to have_enqueued_job(Auth::SendPasswordResetJob).with(user.id)
      expect { gql(request_reset, variables: { input: { email: "nobody@example.test" } }) }
        .to have_enqueued_job(Auth::SendPasswordResetJob).with(nil)
    end

    it "stores only a keyed digest of the code" do
      ask_for_reset
      code = code_from_email
      stored = OneTimeCode.find_by!(user_id: user.id).code_digest

      expect(stored).to eq(OneTimeCode.digest(user_id: user.id, purpose: "password_reset", code:))
      expect(stored).not_to eq(Digest::SHA256.hexdigest(code))
      expect(stored).not_to include(code)
    end

    it "expires the code after 10 minutes" do
      ask_for_reset

      expect(OneTimeCode.find_by!(user_id: user.id).expires_at).to be_within(5.seconds).of(10.minutes.from_now)
    end

    it "works for a locked account" do
      5.times { login_with("wrong password 1") }
      expect(user.reload.access_locked?).to be(true)

      ask_for_reset

      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it "sends no second mail inside 60 seconds, and answers the same" do
      first = ask_for_reset
      again = ask_for_reset

      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(again).to eq(first)
    end

    it "sends a new code after 60 seconds, and the old code stops working" do
      ask_for_reset
      old_code = code_from_email
      travel 61.seconds
      ask_for_reset
      new_code = code_from_email

      expect(ActionMailer::Base.deliveries.size).to eq(2)
      expect(OneTimeCode.where(user_id: user.id).count).to eq(1)
      expect(invalid_code?(reset_with(old_code))).to be(true) unless old_code == new_code
      expect(reset_with(new_code).dig("data", "resetPassword", "success")).to be(true)
    end

    it "needs no token and ignores a garbage one" do
      gql(request_reset, variables: { input: { email: "person@example.test" } }, token: "garbage")

      expect(response.parsed_body.dig("data", "requestPasswordReset", "success")).to be(true)
    end
  end

  describe "resetPassword" do
    before { ask_for_reset }

    it "sets the new password: the new one logs in, the old one does not" do
      body = reset_with(code_from_email)

      expect(body.dig("data", "resetPassword")).to eq("success" => true, "errors" => [])
      expect(login_with(new_password)).to be_present
      expect(login_with("correct horse battery")).to be_nil
    end

    it "accepts the email in another case" do
      body = reset_with(code_from_email, email: "PERSON@Example.test")

      expect(body.dig("data", "resetPassword", "success")).to be(true)
    end

    it "never puts the password or the code in the response" do
      code = code_from_email
      reset_with(code)

      expect(response.body).not_to include(new_password, code)
    end

    it "works once: the same code is INVALID_CODE the second time" do
      code = code_from_email
      reset_with(code)

      expect(invalid_code?(reset_with(code, password: "yet another password"))).to be(true)
      expect(OneTimeCode.where(user_id: user.id)).to be_empty
      expect(login_with(new_password)).to be_present
    end

    it "refuses an expired code, and accepts one just inside 10 minutes" do
      code = code_from_email
      travel 9.minutes + 50.seconds
      expect(reset_with(code).dig("data", "resetPassword", "success")).to be(true)

      ask_for_reset
      expired = code_from_email
      travel 10.minutes + 1.second

      expect(invalid_code?(reset_with(expired))).to be(true)
    end

    it "refuses a wrong code, and a code in a wrong format" do
      expect(invalid_code?(reset_with(wrong_code))).to be(true)
      [ "", "abc123", "12345", "1234567", " 123456", "123456\n", "1' OR '1'='1" ].each do |bad|
        expect(invalid_code?(reset_with(bad))).to be(true)
      end
    end

    it "answers the same for a wrong code, an unknown email, a reused code, and an expired code" do
      code = code_from_email
      wrong = reset_with(wrong_code)
      unknown_email = reset_with(code, email: "nobody@example.test")
      reset_with(code)
      reused = reset_with(code)
      ask_for_reset
      expired_code = code_from_email
      travel 11.minutes
      expired = reset_with(expired_code)

      expect([ wrong, unknown_email, reused, expired ].uniq.size).to eq(1)
      expect(wrong.dig("data", "resetPassword", "errors", 0)).to eq(
        "message" => "This code is invalid or has expired", "path" => [ "input" ], "code" => "INVALID_CODE"
      )
    end

    it "does not accept the code of another user" do
      other = create(:user, email: "other@example.test", password: "other long password")
      code = code_from_email

      expect(invalid_code?(reset_with(code, email: other.email))).to be(true)
      expect(other.reload.valid_password?("other long password")).to be(true)
    end

    it "kills the code after 5 wrong guesses, even for the right code" do
      code = code_from_email
      guess = wrong_code
      5.times { reset_with(guess) }

      expect(OneTimeCode.where(user_id: user.id)).to be_empty
      expect(invalid_code?(reset_with(code))).to be(true)
      expect(login_with("correct horse battery")).to be_present
    end

    it "counts wrong guesses and still accepts the right code on the 5th try" do
      code = code_from_email
      guess = wrong_code
      4.times { reset_with(guess) }
      expect(OneTimeCode.find_by!(user_id: user.id).attempts).to eq(4)

      expect(reset_with(code).dig("data", "resetPassword", "success")).to be(true)
    end

    it "needs a new request after the code is dead, and the new code works" do
      guess = wrong_code
      5.times { reset_with(guess) }
      travel 61.seconds
      ask_for_reset

      expect(reset_with(code_from_email).dig("data", "resetPassword", "success")).to be(true)
    end

    it "returns VALIDATION_FAILED for a weak password, and the code still works afterwards" do
      code = code_from_email
      body = reset_with(code, password: "short")

      expect(body.dig("data", "resetPassword", "success")).to be(false)
      expect(body.dig("data", "resetPassword", "errors")).to include(
        a_hash_including("code" => "VALIDATION_FAILED", "path" => [ "input", "password" ])
      )
      expect(OneTimeCode.find_by!(user_id: user.id).attempts).to eq(0)
      expect(login_with("correct horse battery")).to be_present
      expect(reset_with(code).dig("data", "resetPassword", "success")).to be(true)
    end

    it "tells nothing about the password to someone who does not have the code" do
      body = reset_with(wrong_code, password: "short")

      expect(invalid_code?(body)).to be(true)
    end

    it "rejects a password longer than bcrypt reads" do
      body = reset_with(code_from_email, password: "a" * (ValidationRules::PASSWORD_MAX_BYTES + 1))

      expect(body.dig("data", "resetPassword", "errors", 0, "code")).to eq("VALIDATION_FAILED")
    end

    it "ends every session of the user" do
      session = token_for(user)
      expect(gql(me, token: session).dig("data", "me", "email")).to eq("person@example.test")

      reset_with(code_from_email)

      expect(gql(me, token: session).dig("errors", 0, "extensions", "code")).to eq("UNAUTHENTICATED")
      expect(user.allowlisted_jwts.count).to eq(0)
    end

    it "does not log the user in" do
      expect { reset_with(code_from_email) }.not_to change(AllowlistedJwt, :count)
    end

    it "unlocks a locked account" do
      5.times { login_with("wrong password 1") }
      expect(user.reload.access_locked?).to be(true)

      reset_with(code_from_email)

      expect(user.reload.access_locked?).to be(false)
      expect(login_with(new_password)).to be_present
    end

    it "needs no login and ignores a garbage Authorization token" do
      gql(reset_password, variables: { input: { email: "person@example.test", code: code_from_email, password: new_password } }, token: "garbage")

      expect(response.parsed_body.dig("data", "resetPassword", "success")).to be(true)
    end

    it "never returns the text of an unknown error" do
      allow(Auth::ResetPassword).to receive(:call).and_raise(StandardError, "secret detail from inside")

      body = reset_with(code_from_email)

      expect(response.body).not_to include("secret detail")
      expect(body["errors"].first).to include("extensions" => { "code" => "INTERNAL_ERROR" })
    end
  end
end
