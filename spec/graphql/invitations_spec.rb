require "rails_helper"

RSpec.describe "Invitations", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { create(:user, :super_admin) }
  let(:admin_token) { token_for(admin) }
  let(:password) { "correct horse battery" }

  let(:invite_user) { "mutation($i: InviteUserInput!) { inviteUser(input: $i) { success errors { message path code } } }" }
  let(:accept_invitation) { "mutation($i: AcceptInvitationInput!) { acceptInvitation(input: $i) { token user { id email role } errors { message path code } } }" }
  let(:revoke_invitation) { "mutation($i: RevokeInvitationInput!) { revokeInvitation(input: $i) { success errors { message path code } } }" }
  let(:resend_invitation) { "mutation($i: ResendInvitationInput!) { resendInvitation(input: $i) { success errors { message path code } } }" }

  before { ActionMailer::Base.deliveries.clear }

  def error_code(body) = body.dig("errors", 0, "extensions", "code")

  # Sends the request and runs the email job, like Sidekiq would.
  def run_jobs(&) = perform_enqueued_jobs(&)

  def invite(email, role: "MEMBER", token: admin_token)
    input = { email:, role: }.compact
    run_jobs { gql(invite_user, variables: { i: input }, token:) }
  end

  def resend(email, token: admin_token) = run_jobs { gql(resend_invitation, variables: { i: { email: } }, token:) }

  def revoke(email, token: admin_token) = gql(revoke_invitation, variables: { i: { email: } }, token:)

  # The token exactly as the invitee gets it: from the link in the last email.
  def emailed_token
    ActionMailer::Base.deliveries.last.text_part.body.decoded[/token=([\w-]+)/, 1]
  end

  def accept(token, pass = password, extra = {})
    gql(accept_invitation, variables: { i: { invitationToken: token, password: pass }.merge(extra) })
  end

  def accept_code(body) = body.dig("data", "acceptInvitation", "errors", 0, "code")

  describe "inviteUser" do
    it "stores an invitation with the given role, emails the link, and keeps only the digest" do
      body = invite("fresh@example.test")

      invitation = Invitation.find_by!(email: "fresh@example.test")
      expect(body.dig("data", "inviteUser")).to eq("success" => true, "errors" => [])
      expect(invitation).to have_attributes(role: "member", inviter_id: admin.id)
      expect(invitation.expires_at).to be_within(1.minute).of(Invitation::LIFETIME.from_now)
      expect(ActionMailer::Base.deliveries.map(&:to)).to eq([ [ "fresh@example.test" ] ])
      expect(invitation.token_digest).to eq(Invitation.digest(emailed_token))
      expect(invitation.attributes.values.map(&:to_s)).not_to include(emailed_token)
    end

    it "lets a super_admin ask for member explicitly" do
      invite("fresh@example.test", role: "MEMBER")

      expect(Invitation.find_by!(email: "fresh@example.test").role).to eq("member")
    end

    it "does not offer super_admin: the role argument only lists MEMBER, so even a super_admin cannot ask for it" do
      expect(Types::InvitationRoleEnum.values.keys).to eq([ "MEMBER" ])
      expect(invite("boss@example.test", role: "SUPER_ADMIN")["errors"]).to be_present
      expect(Invitation.count).to eq(0)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "keeps the policy as a second wall: a super_admin invitation record is still refused" do
      expect(InvitationPolicy.new(admin, Invitation.new(email: "boss@example.test", role: "super_admin")).create?).to be(false)
    end

    it "puts only the invitation id in the job arguments" do
      gql(invite_user, variables: { i: { email: "fresh@example.test", role: "MEMBER" } }, token: admin_token)

      expect(enqueued_jobs.map { |job| job["arguments"] }).to eq([ [ Invitation.find_by!(email: "fresh@example.test").id ] ])
    end

    it "normalizes the address" do
      invite("  Fresh@Example.TEST ")

      expect(Invitation.pluck(:email)).to eq([ "fresh@example.test" ])
    end

    it "answers exactly the same for an email that already has an account, and sends nothing" do
      create(:user, email: "taken@example.test")

      fresh = invite("fresh@example.test")
      ActionMailer::Base.deliveries.clear
      taken = invite("taken@example.test")

      expect(taken).to eq(fresh)
      expect(Invitation.where(email: "taken@example.test")).to be_empty
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "enqueues one job for a new and for an existing email, so the work in the request is the same" do
      create(:user, email: "taken@example.test")

      %w[fresh@example.test taken@example.test].each do |email|
        expect { gql(invite_user, variables: { i: { email:, role: "MEMBER" } }, token: admin_token) }.to have_enqueued_job(Invitations::SendInvitationJob).once
      end
    end

    it "reuses the open invitation when the same email is invited again (one row, no second mail inside the cooldown)" do
      invite("fresh@example.test")
      invite("fresh@example.test")

      expect(Invitation.where(email: "fresh@example.test").pluck(:role)).to eq([ "member" ])
      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it "can invite again after the earlier invitation was used" do
      invite("fresh@example.test")
      accept(emailed_token)
      User.find_by!(email: "fresh@example.test").destroy!

      invite("fresh@example.test")

      expect(Invitation.where(email: "fresh@example.test").count).to eq(2)
    end

    it "rejects a badly formed or empty email with VALIDATION_FAILED" do
      [ "not-an-email", "", "a" * 250 + "@example.test" ].each do |email|
        body = invite(email)

        expect(body.dig("data", "inviteUser", "errors", 0, "code")).to eq("VALIDATION_FAILED")
      end
      expect(Invitation.count).to eq(0)
    end

    it "rejects an unknown role and extra input fields" do
      expect(gql(invite_user, variables: { i: { email: "a@example.test", role: "OWNER" } }, token: admin_token)["errors"]).to be_present
      expect(gql(invite_user, variables: { i: { email: "a@example.test", inviterId: SecureRandom.uuid, role: "MEMBER" } }, token: admin_token)["errors"]).to be_present
      expect(Invitation.count).to eq(0)
    end

    it "requires the role: a request without it is rejected and invites nobody" do
      body = gql(invite_user, variables: { i: { email: "fresh@example.test" } }, token: admin_token)

      expect(body["errors"]).to be_present
      expect(Invitation.count).to eq(0)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "denies a member with FORBIDDEN, and creates nothing" do
      body = invite("fresh@example.test", token: token_for(create(:user)))

      expect(error_code(body)).to eq("FORBIDDEN")
      expect(Invitation.count).to eq(0)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "answers 401 before 403 before 422: a bad email gets UNAUTHENTICATED with no login and FORBIDDEN for a member" do
      member_token = token_for(create(:user))

      [ "null", "", "not-an-email" ].each do |email|
        expect(error_code(invite(email, token: nil))).to eq("UNAUTHENTICATED")
        expect(error_code(revoke(email, token: nil))).to eq("UNAUTHENTICATED")
        expect(error_code(resend(email, token: nil))).to eq("UNAUTHENTICATED")
        expect(error_code(invite(email, token: member_token))).to eq("FORBIDDEN")
        expect(error_code(revoke(email, token: member_token))).to eq("FORBIDDEN")
        expect(error_code(resend(email, token: member_token))).to eq("FORBIDDEN")
      end
    end

    it "answers UNAUTHENTICATED only, with no data and no hint about the arguments, for a request with bad arguments and no login" do
      bad = [
        [ invite_user, { email: "a@example.test", role: "SUPER_ADMIN" } ],
        [ invite_user, { role: "OWNER" } ],
        [ invite_user, {} ],
        [ revoke_invitation, { email: nil } ],
        [ resend_invitation, { email: 5 } ],
        [ revoke_invitation, { email: "null", extra: 1 } ]
      ]

      bad.each do |query, input|
        body = gql(query, variables: { i: input })

        expect(body["errors"].map { |e| e.dig("extensions", "code") }).to eq([ "UNAUTHENTICATED" ])
        expect(body["data"]).to be_nil
      end
    end

    it "says which field is wrong, in plain words, for a super_admin" do
      %i[invite revoke resend].each do |operation|
        body = public_send(operation, "")
        errors = body.dig("data", "#{operation}#{operation == :invite ? 'User' : 'Invitation'}", "errors")

        expect(errors).to eq([ { "message" => "Email is required", "path" => %w[input email], "code" => "VALIDATION_FAILED" } ])
      end
    end

    it "denies nobody logged in, or a garbage token, with UNAUTHENTICATED" do
      expect(error_code(invite("fresh@example.test", token: nil))).to eq("UNAUTHENTICATED")
      expect(error_code(invite("fresh@example.test", token: "garbage"))).to eq("UNAUTHENTICATED")
      expect(Invitation.count).to eq(0)
    end

    it "denies a super_admin whose token was revoked by logout" do
      gql("mutation { logout(input: {}) { success } }", token: admin_token)

      expect(error_code(invite("fresh@example.test"))).to eq("UNAUTHENTICATED")
    end
  end

  describe "acceptInvitation" do
    before { invite("fresh@example.test") }

    let(:token) { emailed_token }

    it "says a field is required (not invalid) when it is empty, and names the field" do
      errors = ->(body) { body.dig("data", "acceptInvitation", "errors").map { |e| e.slice("message", "path", "code") } }

      expect(errors.call(accept("", ""))).to contain_exactly(
        { "message" => "Invitation token is required", "path" => %w[input invitationToken], "code" => "VALIDATION_FAILED" },
        { "message" => "Password is required", "path" => %w[input password], "code" => "VALIDATION_FAILED" }
      )
      expect(errors.call(accept("   ", password)).map { |e| e["path"] }).to eq([ %w[input invitationToken] ])
      expect(errors.call(accept(token, "")).map { |e| e["path"] }).to eq([ %w[input password] ])
      expect(Invitation.find_by!(email: "fresh@example.test")).to be_open # an empty field uses nothing up
    end

    it "still says INVALID_INVITATION for a filled token that is wrong" do
      expect(accept_code(accept("wrong-token", password))).to eq("INVALID_INVITATION")
    end

    it "creates the user with the invited role, logs them in, and uses the invitation up" do
      body = accept(token)

      payload = body.dig("data", "acceptInvitation")
      user = User.find_by!(email: "fresh@example.test")
      expect(payload["errors"]).to eq([])
      expect(payload["user"]).to include("email" => "fresh@example.test", "role" => "MEMBER")
      expect(user.valid_password?(password)).to be(true)
      expect(gql("{ me { id } }", token: payload["token"]).dig("data", "me", "id")).to eq(user.id)
      expect(Invitation.find_by!(email: "fresh@example.test")).to have_attributes(accepted_at: be_present, token_digest: nil)
    end

    it "gives the role stored on the invitation (never one from the client)" do
      create(:invitation, email: "boss@example.test", role: "super_admin", token_digest: Invitation.digest("T" * 43))

      accept("T" * 43)

      expect(User.find_by!(email: "boss@example.test")).to be_super_admin
    end

    it "works while public sign up is off, and needs no login" do
      expect(Rails.configuration.x.allow_public_sign_up).to be(false)

      expect(accept(token).dig("data", "acceptInvitation", "token")).to be_present
    end

    it "does not take a role or an email from the client" do
      expect(accept(token, password, { role: "SUPER_ADMIN" })["errors"]).to be_present
      expect(accept(token, password, { email: "other@example.test" })["errors"]).to be_present
      expect(User.where(email: "fresh@example.test")).to be_empty
    end

    it "fails the second time with INVALID_INVITATION (used twice)" do
      accept(token)

      expect { expect(accept_code(accept(token, "another long password"))).to eq("INVALID_INVITATION") }.not_to change(User, :count)
    end

    it "fails after 7 days with INVALID_INVITATION (expired)" do
      travel(Invitation::LIFETIME + 1.minute) do
        expect { expect(accept_code(accept(token))).to eq("INVALID_INVITATION") }.not_to change(User, :count)
      end
    end

    it "still works just before it expires" do
      travel(Invitation::LIFETIME - 1.minute) do
        expect(accept(token).dig("data", "acceptInvitation", "token")).to be_present
      end
    end

    it "fails after a revoke with INVALID_INVITATION" do
      revoke("fresh@example.test")

      expect { expect(accept_code(accept(token))).to eq("INVALID_INVITATION") }.not_to change(User, :count)
    end

    it "fails for a wrong or malformed token with the same answer" do
      wrong = [ Invitation.generate_token, "short", "a" * 10_000, "' OR 1=1 --", token.reverse ]
      bodies = wrong.map { |value| accept(value) }

      expect(bodies.map { |body| accept_code(body) }).to all(eq("INVALID_INVITATION"))
      expect(bodies.map { |body| body.dig("data", "acceptInvitation", "errors", 0, "message") }.uniq).to eq([ Errors::INVALID_INVITATION.message ])
      expect(User.where(email: "fresh@example.test")).to be_empty
    end

    it "does not accept the digest stored in the database as a token" do
      digest = Invitation.find_by!(email: "fresh@example.test").token_digest

      expect(accept_code(accept(digest))).to eq("INVALID_INVITATION")
    end

    it "does not use the invitation up on a weak password" do
      expect(accept("#{token}", "short").dig("data", "acceptInvitation", "errors", 0, "code")).to eq("VALIDATION_FAILED")
      expect(User.where(email: "fresh@example.test")).to be_empty

      expect(accept(token).dig("data", "acceptInvitation", "token")).to be_present
    end

    it "says INVALID_INVITATION, not that the account exists, when the email got an account in the meantime" do
      create(:user, email: "fresh@example.test")

      body = accept(token)

      expect(accept_code(body)).to eq("INVALID_INVITATION")
      expect(body.dig("data", "acceptInvitation", "errors", 0, "message")).not_to match(/taken|exists|account/i)
    end

    it "lets exactly one of several parallel accepts win" do
      results = Array.new(4) { Thread.new { ActiveRecord::Base.connection_pool.with_connection { Invitations::Accept.call(token:, password:) } } }.map(&:value)

      expect(results.count(&:success?)).to eq(1)
      expect(User.where(email: "fresh@example.test").count).to eq(1)
    end

    it "stops the old link when a new one is sent (resend)" do
      old = token
      travel(Invitation::RESEND_AFTER + 1.second) { resend("fresh@example.test") }
      fresh = emailed_token

      expect(fresh).not_to eq(old)
      expect(accept_code(accept(old))).to eq("INVALID_INVITATION")
      expect(accept(fresh).dig("data", "acceptInvitation", "token")).to be_present
    end
  end

  describe "revokeInvitation" do
    before { invite("fresh@example.test") }

    it "revokes the open invitation and clears its token digest" do
      body = revoke("fresh@example.test")

      expect(body.dig("data", "revokeInvitation")).to eq("success" => true, "errors" => [])
      expect(Invitation.find_by!(email: "fresh@example.test")).to have_attributes(revoked_at: be_present, token_digest: nil)
    end

    it "answers the same for an address that was never invited" do
      expect(revoke("nobody@example.test")).to eq(revoke("fresh@example.test").merge(revoke("nobody@example.test")))
      expect(revoke("nobody@example.test").dig("data", "revokeInvitation", "success")).to be(true)
    end

    it "is allowed again for the same email after a revoke (a new invitation)" do
      revoke("fresh@example.test")
      travel(Invitation::RESEND_AFTER + 1.second) { invite("fresh@example.test") }

      expect(Invitation.open.where(email: "fresh@example.test").count).to eq(1)
      expect(Invitation.where(email: "fresh@example.test").count).to eq(2)
    end

    it "rejects a badly formed email" do
      expect(revoke("nope").dig("data", "revokeInvitation", "errors", 0, "code")).to eq("VALIDATION_FAILED")
    end

    it "denies a member with FORBIDDEN and changes nothing" do
      expect(error_code(revoke("fresh@example.test", token: token_for(create(:user))))).to eq("FORBIDDEN")
      expect(Invitation.find_by!(email: "fresh@example.test").revoked_at).to be_nil
    end

    it "denies nobody logged in with UNAUTHENTICATED" do
      expect(error_code(revoke("fresh@example.test", token: nil))).to eq("UNAUTHENTICATED")
      expect(Invitation.find_by!(email: "fresh@example.test").revoked_at).to be_nil
    end
  end

  describe "resendInvitation" do
    before { invite("fresh@example.test") }

    it "sends a fresh link after the cooldown and restarts the expiry" do
      first = emailed_token

      travel(1.day) { resend("fresh@example.test", token: token_for(admin)) } # the admin token of 1 day ago may have expired

      expect(ActionMailer::Base.deliveries.size).to eq(2)
      expect(emailed_token).not_to eq(first)
      expect(Invitation.find_by!(email: "fresh@example.test").expires_at).to be > (Invitation::LIFETIME - 1.minute).from_now
    end

    it "revives an invitation that expired" do
      stale = emailed_token
      travel(Invitation::LIFETIME + 1.day) { resend("fresh@example.test", token: token_for(admin)) }

      expect(emailed_token).not_to eq(stale)
      expect(accept(emailed_token).dig("data", "acceptInvitation", "token")).to be_present
    end

    it "sends nothing inside the 60 second cooldown, and still answers success" do
      body = resend("fresh@example.test")

      expect(body.dig("data", "resendInvitation", "success")).to be(true)
      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it "reopens a revoked invitation and sends a fresh link that works (the old link stays dead)" do
      old_token = emailed_token
      revoke("fresh@example.test")
      ActionMailer::Base.deliveries.clear

      body = resend("fresh@example.test") # no waiting: the cooldown of the first send does not block a reopen

      expect(body.dig("data", "resendInvitation")).to eq("success" => true, "errors" => [])
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(Invitation.find_by!(email: "fresh@example.test")).to have_attributes(revoked_at: nil, role: "member", token_digest: be_present)
      expect(accept(old_token).dig("data", "acceptInvitation", "errors", 0, "code")).to eq("INVALID_INVITATION")
      expect(accept(emailed_token).dig("data", "acceptInvitation", "token")).to be_present
    end

    it "uses the open invitation, and not an older revoked one, when both exist" do
      revoke("fresh@example.test")
      travel(Invitation::RESEND_AFTER + 1.second) { invite("fresh@example.test") }
      ActionMailer::Base.deliveries.clear

      travel(3.minutes) { resend("fresh@example.test") }

      expect(Invitation.where(email: "fresh@example.test").pluck(:revoked_at).count(nil)).to eq(1)
      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it "does not reopen a revoked invitation when the email already has an account" do
      revoke("fresh@example.test")
      create(:user, email: "fresh@example.test")
      ActionMailer::Base.deliveries.clear

      travel(2.minutes) { resend("fresh@example.test") }

      expect(Invitation.find_by!(email: "fresh@example.test").revoked_at).to be_present
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "sends nothing for a used invitation or an address never invited, and answers the same as for a reopen" do
      invite("used@example.test")
      accept(emailed_token)
      ActionMailer::Base.deliveries.clear

      answers = travel(2.minutes) { %w[used@example.test nobody@example.test].map { |email| resend(email) } }

      expect(answers.uniq.size).to eq(1)
      expect(answers.first.dig("data", "resendInvitation", "success")).to be(true)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "rejects a badly formed email" do
      expect(resend("nope").dig("data", "resendInvitation", "errors", 0, "code")).to eq("VALIDATION_FAILED")
    end

    it "denies a member with FORBIDDEN and sends nothing" do
      ActionMailer::Base.deliveries.clear

      travel(2.minutes) { expect(error_code(resend("fresh@example.test", token: token_for(create(:user))))).to eq("FORBIDDEN") }
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "denies nobody logged in with UNAUTHENTICATED" do
      expect(error_code(resend("fresh@example.test", token: nil))).to eq("UNAUTHENTICATED")
    end
  end

  describe "signUp" do
    let(:sign_up) { "mutation($i: SignUpInput!) { signUp(input: $i) { token errors { code } } }" }
    let(:input) { { i: { email: "walkin@example.test", password: } } }

    it "is FORBIDDEN by default (the template is invite only), says why and what to do, and creates no user" do
      expect do
        body = gql(sign_up, variables: input)

        expect(error_code(body)).to eq("FORBIDDEN")
        expect(body.dig("errors", 0, "message")).to eq("Sign up is closed to the public. Ask an administrator to send you an invitation")
      end.not_to change(User, :count)
    end

    it "works when the server turns public sign up on", :public_sign_up do
      expect(gql(sign_up, variables: input).dig("data", "signUp", "token")).to be_present
    end
  end
end
