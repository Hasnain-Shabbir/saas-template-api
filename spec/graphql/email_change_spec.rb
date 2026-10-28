require "rails_helper"

RSpec.describe "Email change", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:old_email) { "person@example.test" }
  let(:new_email) { "fresh@example.test" }
  let(:password) { "correct horse battery" }
  let!(:user) { create(:user, email: old_email, password:) }
  let(:token) { token_for(user) }

  let(:request_change) do
    <<~GQL
      mutation($input: RequestEmailChangeInput!) {
        requestEmailChange(input: $input) { success errors { message path code } }
      }
    GQL
  end
  let(:confirm_change) do
    <<~GQL
      mutation($input: ConfirmEmailChangeInput!) {
        confirmEmailChange(input: $input) { success errors { message path code } }
      }
    GQL
  end
  let(:me) { "{ me { id email } }" }

  before { ActionMailer::Base.deliveries.clear }

  def ask_for_change(email = new_email, as: token, with: password)
    perform_enqueued_jobs { gql(request_change, variables: { input: { newEmail: email, password: with } }, token: as) }
  end

  # The code only exists in the email (the database keeps a digest), so the tests read it from there, like a user would.
  def code_from_email
    ActionMailer::Base.deliveries.reverse.find { |mail| mail.subject == EmailChangeMailer::CODE_SUBJECT }
                      .text_part.body.decoded[/^(\d{6})$/, 1]
  end

  def confirm_with(code, as: token)
    perform_enqueued_jobs { gql(confirm_change, variables: { input: { code: } }, token: as) }
  end

  def wrong_code
    code_from_email == "000000" ? "111111" : "000000"
  end

  def invalid_code?(body)
    body.dig("data", "confirmEmailChange", "errors", 0, "code") == "INVALID_CODE" && body.dig("data", "confirmEmailChange", "success") == false
  end

  def error_code(body)
    body.dig("errors", 0, "extensions", "code")
  end

  describe "requestEmailChange" do
    it "emails a 6-digit code to the NEW address only, and leaves the login email alone" do
      body = ask_for_change

      mail = ActionMailer::Base.deliveries.last
      expect(body.dig("data", "requestEmailChange")).to eq("success" => true, "errors" => [])
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(mail.to).to eq([ new_email ])
      expect(mail.from).to eq([ Rails.configuration.x.mailer_from ])
      expect(code_from_email).to match(ValidationRules::OTP_FORMAT)
      expect(mail.html_part.body.decoded).to include(code_from_email)
      expect(user.reload.email).to eq(old_email)
      expect(user.pending_email).to eq(new_email)
    end

    it "keeps the code out of the subject" do
      ask_for_change

      expect(ActionMailer::Base.deliveries.last.subject).not_to match(/\d{6}/)
    end

    it "stores only a keyed digest of the code, valid for 10 minutes" do
      ask_for_change
      stored = OneTimeCode.find_by!(user_id: user.id, purpose: "email_change")

      expect(stored.code_digest).to eq(OneTimeCode.digest(user_id: user.id, purpose: "email_change", code: code_from_email))
      expect(stored.code_digest).not_to eq(Digest::SHA256.hexdigest(code_from_email))
      expect(stored.expires_at).to be_within(5.seconds).of(10.minutes.from_now)
    end

    it "does not touch a password reset code" do
      OneTimeCode.create!(user:, purpose: "password_reset", code_digest: "x", expires_at: 5.minutes.from_now)

      ask_for_change

      expect(OneTimeCode.where(user_id: user.id).pluck(:purpose)).to match_array(%w[password_reset email_change])
    end

    it "normalizes the new email" do
      ask_for_change("  Fresh@Example.TEST ")

      expect(user.reload.pending_email).to eq("fresh@example.test")
      expect(ActionMailer::Base.deliveries.last.to).to eq([ "fresh@example.test" ])
    end

    it "needs the current password: a wrong one is INVALID_CREDENTIALS and sends nothing" do
      body = ask_for_change(with: "wrong password 1")

      expect(body.dig("data", "requestEmailChange")["success"]).to be(false)
      expect(body.dig("data", "requestEmailChange", "errors", 0, "code")).to eq("INVALID_CREDENTIALS")
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(user.reload.pending_email).to be_nil
      expect(OneTimeCode.count).to eq(0)
    end

    it "counts wrong passwords like a failed login: 5 lock the account" do
      5.times { ask_for_change(with: "wrong password 1") }

      expect(user.reload.access_locked?).to be(true)
      expect(error_code(ask_for_change)).to eq("UNAUTHENTICATED") # a locked account's token is refused, nothing is sent
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "keeps counting across other logged-in requests (the count is not reset by authentication)" do
      2.times do
        ask_for_change(with: "wrong password 1")
        gql(me, token:)
      end

      expect(user.reload.failed_attempts).to eq(2)
    end

    it "refuses the token of the locked account, and a password reset unlocks it" do
      5.times { ask_for_change(with: "wrong password 1") }

      expect(error_code(gql(me, token:))).to eq("UNAUTHENTICATED")

      code = perform_enqueued_jobs do
        gql("mutation { requestPasswordReset(input: { email: \"#{old_email}\" }) { success } }")
        ActionMailer::Base.deliveries.last.text_part.body.decoded[/^(\d{6})$/, 1]
      end
      gql("mutation($i: ResetPasswordInput!) { resetPassword(input: $i) { success } }",
          variables: { i: { email: old_email, code:, password: "a brand new password" } })

      expect(user.reload.access_locked?).to be(false)
      expect(gql(me, token: token_for(user)).dig("data", "me", "email")).to eq(old_email)
    end

    it "resets the failed password count after a right password" do
      2.times { ask_for_change(with: "wrong password 1") }
      ask_for_change

      expect(user.reload.failed_attempts).to eq(0)
    end

    it "is denied without a login" do
      expect(error_code(ask_for_change(as: nil))).to eq("UNAUTHENTICATED")
      expect(error_code(ask_for_change(as: "garbage"))).to eq("UNAUTHENTICATED")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "asks for an email when it is empty or blank" do
      [ "", "   " ].each do |email|
        payload = ask_for_change(email).dig("data", "requestEmailChange")

        expect(payload["success"]).to be(false)
        expect(payload["errors"]).to eq([ { "message" => "New email is required", "path" => %w[input newEmail], "code" => "VALIDATION_FAILED" } ])
      end
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "rejects text that is not a valid email, or is too long" do
      [ "123124", "not-an-email", "a@b", "#{'a' * ValidationRules::EMAIL_MAX_LENGTH}@example.test" ].each do |email|
        payload = ask_for_change(email).dig("data", "requestEmailChange")

        expect(payload["errors"]).to eq([ { "message" => "New email is invalid", "path" => %w[input newEmail], "code" => "VALIDATION_FAILED" } ])
      end
      expect(user.reload.pending_email).to be_nil
    end

    it "reports a bad email before a bad password, and a bad email does not count as a failed password" do
      [ "", "not-an-email" ].each do |email|
        payload = ask_for_change(email, with: "").dig("data", "requestEmailChange")

        expect(payload["errors"].map { |e| e["code"] }).to eq([ "VALIDATION_FAILED" ])
      end
      expect(user.reload.failed_attempts).to eq(0)
    end

    describe "when the new email is taken" do
      before { create(:user, email: "taken@example.test") }

      it "answers exactly the same as for a free email, and sends nothing" do
        free = ask_for_change("free@example.test")
        ActionMailer::Base.deliveries.clear
        travel 61.seconds
        taken = ask_for_change("TAKEN@example.test")

        expect(taken).to eq(free)
        expect(taken.dig("data", "requestEmailChange")).to eq("success" => true, "errors" => [])
        expect(ActionMailer::Base.deliveries).to be_empty
        expect(user.reload.pending_email).to be_nil
        expect(OneTimeCode.where(user_id: user.id)).to be_empty
      end

      it "treats the user's own email the same way" do
        body = ask_for_change(old_email)

        expect(body.dig("data", "requestEmailChange")).to eq("success" => true, "errors" => [])
        expect(ActionMailer::Base.deliveries).to be_empty
        expect(user.reload.pending_email).to be_nil
      end

      it "enqueues a job with the user id only, like for a free email" do
        expect { gql(request_change, variables: { input: { newEmail: "taken@example.test", password: } }, token:) }
          .to have_enqueued_job(Auth::SendEmailChangeCodeJob).with(user.id)
        expect { gql(request_change, variables: { input: { newEmail: "free@example.test", password: } }, token:) }
          .to have_enqueued_job(Auth::SendEmailChangeCodeJob).with(user.id)
      end

      it "drops an earlier pending request, so its code no longer works" do
        ask_for_change
        old_code = code_from_email
        travel 61.seconds
        ask_for_change("taken@example.test")

        expect(invalid_code?(confirm_with(old_code))).to be(true)
        expect(user.reload.email).to eq(old_email)
      end
    end

    it "sends no second mail inside 60 seconds, keeps the first address, and answers the same" do
      first = ask_for_change
      again = ask_for_change("other@example.test")

      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(again).to eq(first)
      expect(user.reload.pending_email).to eq(new_email) # the code was sent there, so it must stay the address it opens
    end

    it "sends a new code to the new address after 60 seconds, and the old code stops working" do
      ask_for_change
      old_code = code_from_email
      travel 61.seconds
      ask_for_change("other@example.test")

      expect(ActionMailer::Base.deliveries.last.to).to eq([ "other@example.test" ])
      expect(OneTimeCode.where(user_id: user.id, purpose: "email_change").count).to eq(1)
      expect(invalid_code?(confirm_with(old_code))).to be(true) unless old_code == code_from_email
      expect(confirm_with(code_from_email).dig("data", "confirmEmailChange", "success")).to be(true)
      expect(user.reload.email).to eq("other@example.test")
    end

    it "never puts the password or the code in the response" do
      ask_for_change

      expect(response.body).not_to include(password, code_from_email)
    end

    it "never returns the text of an unknown error" do
      allow(Auth::RequestEmailChange).to receive(:call).and_raise(StandardError, "secret detail from inside")

      body = ask_for_change

      expect(response.body).not_to include("secret detail")
      expect(body["errors"].first).to include("extensions" => { "code" => "INTERNAL_ERROR" })
    end
  end

  describe "confirmEmailChange" do
    before { ask_for_change }

    it "changes the login email: the new one logs in, the old one does not" do
      body = confirm_with(code_from_email)

      expect(body.dig("data", "confirmEmailChange")).to eq("success" => true, "errors" => [])
      expect(user.reload.email).to eq(new_email)
      expect(user.pending_email).to be_nil
      expect(user.valid_password?(password)).to be(true)
      expect(User.find_for_database_authentication(email: new_email)).to eq(user)
      expect(User.find_for_database_authentication(email: old_email)).to be_nil
      expect(gql(me, token:).dig("data", "me", "email")).to eq(new_email)
    end

    it "works once: the same code is INVALID_CODE the second time" do
      code = code_from_email
      confirm_with(code)

      expect(invalid_code?(confirm_with(code))).to be(true)
      expect(OneTimeCode.where(user_id: user.id)).to be_empty
    end

    it "ends every other session, and keeps the one that confirmed" do
      other_session = token_for(user)
      code = code_from_email

      confirm_with(code)

      expect(gql(me, token:).dig("data", "me", "email")).to eq(new_email)
      expect(error_code(gql(me, token: other_session))).to eq("UNAUTHENTICATED")
      expect(user.allowlisted_jwts.count).to eq(1)
    end

    it "sends a notice to the OLD address, without a code or the new address, and then forgets the old address" do
      confirm_with(code_from_email)

      notice = ActionMailer::Base.deliveries.last
      body = notice.text_part.body.decoded + notice.html_part.body.decoded
      expect(notice.to).to eq([ old_email ])
      expect(notice.subject).to eq(EmailChangeMailer::NOTICE_SUBJECT)
      expect(body).not_to match(/\d{6}/)
      expect(body).not_to include(new_email)
      expect(user.reload.previous_email).to be_nil
    end

    it "enqueues the notice job with the user id only" do
      expect { gql(confirm_change, variables: { input: { code: code_from_email } }, token:) }
        .to have_enqueued_job(Auth::SendEmailChangedNoticeJob).with(user.id)
    end

    it "refuses a wrong code, and a code in a wrong format, and changes nothing" do
      expect(invalid_code?(confirm_with(wrong_code))).to be(true)
      [ "", "abc123", "12345", "1234567", " 123456", "123456\n", "1' OR '1'='1" ].each do |bad|
        expect(invalid_code?(confirm_with(bad))).to be(true)
      end
      expect(user.reload.email).to eq(old_email)
      expect(user.pending_email).to eq(new_email)
    end

    it "refuses an expired code, and accepts one just inside 10 minutes" do
      code = code_from_email
      travel 9.minutes + 50.seconds
      expect(confirm_with(code).dig("data", "confirmEmailChange", "success")).to be(true)

      user.reload.update!(email: old_email)
      travel 1.minute
      ask_for_change
      expired = code_from_email
      travel 10.minutes + 1.second

      expect(invalid_code?(confirm_with(expired))).to be(true)
      expect(user.reload.email).to eq(old_email)
    end

    it "answers the same for a wrong code, a reused code, an expired code, and no request at all" do
      code = code_from_email
      wrong = confirm_with(wrong_code)
      confirm_with(code)
      reused = confirm_with(code)
      other = create(:user, password:)
      no_request = confirm_with(code, as: token_for(other))
      user.reload.update!(email: old_email)
      travel 61.seconds
      ask_for_change
      expired_code = code_from_email
      travel 11.minutes
      expired = confirm_with(expired_code)

      expect([ wrong, reused, no_request, expired ].uniq.size).to eq(1)
      expect(wrong.dig("data", "confirmEmailChange", "errors", 0)).to eq(
        "message" => "This code is invalid or has expired", "path" => [ "input" ], "code" => "INVALID_CODE"
      )
    end

    it "kills the code after 5 wrong guesses, even for the right code" do
      code = code_from_email
      guess = wrong_code
      5.times { confirm_with(guess) }

      expect(OneTimeCode.where(user_id: user.id)).to be_empty
      expect(invalid_code?(confirm_with(code))).to be(true)
      expect(user.reload.email).to eq(old_email)
    end

    it "counts wrong guesses and still accepts the right code on the 5th try" do
      code = code_from_email
      guess = wrong_code
      4.times { confirm_with(guess) }
      expect(OneTimeCode.find_by!(user_id: user.id, purpose: "email_change").attempts).to eq(4)

      expect(confirm_with(code).dig("data", "confirmEmailChange", "success")).to be(true)
    end

    it "does not let another user confirm with this code, and does not spend a guess of the real code" do
      code = code_from_email
      intruder = create(:user, email: "intruder@example.test", password:)

      body = confirm_with(code, as: token_for(intruder))

      expect(invalid_code?(body)).to be(true)
      expect(intruder.reload.email).to eq("intruder@example.test")
      expect(user.reload.email).to eq(old_email)
      expect(OneTimeCode.find_by!(user_id: user.id, purpose: "email_change").attempts).to eq(0)
      expect(confirm_with(code).dig("data", "confirmEmailChange", "success")).to be(true)
    end

    it "does not take over a pending change of another user with a guessed code" do
      other = create(:user, email: "other@example.test", password:)

      body = confirm_with(code_from_email, as: token_for(other))

      expect(invalid_code?(body)).to be(true)
      expect(other.reload.email).to eq("other@example.test")
    end

    it "answers INVALID_CODE, and changes nothing, when the address was taken in the meantime" do
      code = code_from_email
      create(:user, email: new_email)

      body = confirm_with(code)

      expect(invalid_code?(body)).to be(true)
      expect(user.reload.email).to eq(old_email)
      expect(user.pending_email).to be_nil
      expect(OneTimeCode.where(user_id: user.id)).to be_empty
      expect(ActionMailer::Base.deliveries.last.subject).not_to eq(EmailChangeMailer::NOTICE_SUBJECT)
    end

    it "keeps the old sessions when the confirm fails" do
      other_session = token_for(user)

      confirm_with(wrong_code)

      expect(gql(me, token: other_session).dig("data", "me", "email")).to eq(old_email)
    end

    it "is denied without a login" do
      expect(error_code(confirm_with(code_from_email, as: nil))).to eq("UNAUTHENTICATED")
      expect(error_code(confirm_with(code_from_email, as: "garbage"))).to eq("UNAUTHENTICATED")
      expect(user.reload.email).to eq(old_email)
    end

    it "denies a token that was ended by logout" do
      session = token

      gql("mutation { logout(input: {}) { success } }", token: session)

      expect(error_code(confirm_with(code_from_email, as: session))).to eq("UNAUTHENTICATED")
    end

    it "never puts the code in the response" do
      code = code_from_email
      confirm_with(code)

      expect(response.body).not_to include(code)
    end
  end
end
