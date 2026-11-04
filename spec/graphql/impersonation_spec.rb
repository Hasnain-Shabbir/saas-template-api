require "rails_helper"

RSpec.describe "Start and stop an impersonation", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:admin) { create(:user, :super_admin, email: "admin@example.test") }
  let!(:member) { create(:user, email: "member@example.test") }

  let(:start) do
    "mutation($i: StartImpersonationInput!) { startImpersonation(input: $i) { token impersonation { id reasonCategory reason startedAt expiresAt target { id email } } errors { message path code } } }"
  end
  let(:stop) { "mutation { stopImpersonation(input: {}) { success errors { message path code } } }" }
  let(:logout) { "mutation { logout(input: {}) { success errors { code } } }" }
  let(:me) { "{ me { id email } }" }

  def error_code(body) = body.dig("errors", 0, "extensions", "code")

  def start_as(user, id: member.id, category: "SUPPORT_REQUEST", reason: nil)
    input = { userId: id, reasonCategory: category }
    input[:reason] = reason if reason
    gql(start, variables: { i: input }, token: user && token_for(user))
  end

  def started_token = start_as(admin).dig("data", "startImpersonation", "token")

  describe "startImpersonation" do
    it "starts a session and returns a token that acts as the member" do
      body = start_as(admin)

      payload = body.dig("data", "startImpersonation")
      expect(payload["errors"]).to eq([])
      expect(payload["impersonation"]).to include("reasonCategory" => "SUPPORT_REQUEST", "reason" => nil)
      expect(payload.dig("impersonation", "target")).to include("id" => member.id, "email" => member.email)
      expect(Time.zone.parse(payload.dig("impersonation", "expiresAt")) - Time.zone.parse(payload.dig("impersonation", "startedAt"))).to be_within(1.second).of(30.minutes)
      expect(gql(me, token: payload["token"]).dig("data", "me", "id")).to eq(member.id)
    end

    it "stores the session with the admin, the member, the category, and the request id" do
      start_as(admin, category: "OTHER", reason: "Checking a billing complaint")

      expect(Impersonation.sole).to have_attributes(impersonator_id: admin.id, target_id: member.id, reason_category: "other",
                                                    reason: "Checking a billing complaint", request_id: response.headers["X-Request-Id"])
    end

    it "does not touch the admin's own token" do
      own = token_for(admin)

      gql(start, variables: { i: { userId: member.id, reasonCategory: "BUG_INVESTIGATION" } }, token: own)

      expect(gql(me, token: own).dig("data", "me", "id")).to eq(admin.id)
    end

    it "ends the session the admin had open, and kills its token (a second device)" do
      first = started_token
      other_member = create(:user)

      start_as(admin, id: other_member.id)

      expect(error_code(gql(me, token: first))).to eq("UNAUTHENTICATED")
      expect(Impersonation.unended.sole.target_id).to eq(other_member.id)
    end

    it "does not return the password hash, tokens, or personal data of the member" do
      body = start_as(admin)

      expect(body.to_json).not_to match(/encrypted_password|password|phone|dateOfBirth|addressLine/i)
    end

    describe "validation" do
      it "needs a note for OTHER" do
        body = start_as(admin, category: "OTHER")

        payload = body.dig("data", "startImpersonation")
        expect(payload["token"]).to be_nil
        expect(payload["impersonation"]).to be_nil
        expect(payload["errors"].first).to include("code" => "VALIDATION_FAILED", "path" => %w[input reason])
        expect(Impersonation.count).to eq(0)
        expect(member.allowlisted_jwts).to be_empty
      end

      it "refuses a note longer than the limit" do
        body = start_as(admin, reason: "a" * (ValidationRules::IMPERSONATION_REASON_MAX_LENGTH + 1))

        expect(body.dig("data", "startImpersonation", "errors", 0, "code")).to eq("VALIDATION_FAILED")
      end

      it "refuses an unknown category (a GraphQL enum)" do
        expect(start_as(admin, category: "FUN")["errors"]).to be_present
        expect(Impersonation.count).to eq(0)
      end
    end

    describe "who can be impersonated" do
      it "refuses a super_admin, with a message that says why" do
        body = start_as(admin, id: create(:user, :super_admin).id)

        error = body.dig("data", "startImpersonation", "errors", 0)
        expect(error).to include("code" => "FORBIDDEN", "message" => Errors::IMPERSONATE_SUPER_ADMIN.message)
        expect(Impersonation.count).to eq(0)
      end

      it "refuses the admin themself" do
        expect(start_as(admin, id: admin.id).dig("data", "startImpersonation", "errors", 0, "message")).to eq(Errors::IMPERSONATE_SUPER_ADMIN.message)
      end

      it "refuses an archived member and an access-revoked member" do
        [ create(:user, archived_at: Time.current), create(:user, access_revoked_at: Time.current) ].each do |blocked|
          body = start_as(admin, id: blocked.id)

          expect(body.dig("data", "startImpersonation", "errors", 0, "message")).to eq(Errors::IMPERSONATE_BLOCKED_USER.message)
        end
        expect(Impersonation.count).to eq(0)
      end

      it "answers NOT_FOUND for an id that does not exist" do
        expect(error_code(start_as(admin, id: SecureRandom.uuid))).to eq("NOT_FOUND")
      end
    end

    describe "who may call it" do
      it "denies a member with FORBIDDEN, whether the id exists or not" do
        stranger = create(:user)

        expect(error_code(start_as(stranger))).to eq("FORBIDDEN")
        expect(error_code(start_as(stranger, id: SecureRandom.uuid))).to eq("FORBIDDEN")
        expect(Impersonation.count).to eq(0)
      end

      it "denies nobody logged in with UNAUTHENTICATED, even with bad input" do
        expect(error_code(start_as(nil))).to eq("UNAUTHENTICATED")
        expect(error_code(start_as(nil, category: "FUN"))).to eq("UNAUTHENTICATED")
      end

      it "denies an impersonation token: no session inside a session" do
        token = started_token

        body = gql(start, variables: { i: { userId: create(:user).id, reasonCategory: "SUPPORT_REQUEST" } }, token:)

        expect(error_code(body)).to eq("FORBIDDEN")
        expect(body.dig("errors", 0, "message")).to eq(Errors::NOT_ALLOWED_WHILE_IMPERSONATING.message)
        expect(Impersonation.count).to eq(1)
      end

      it "denies an archived or access-revoked admin (their tokens are dead)" do
        token = token_for(admin)
        admin.update!(access_revoked_at: Time.current)
        admin.allowlisted_jwts.delete_all

        expect(error_code(gql(start, variables: { i: { userId: member.id, reasonCategory: "SUPPORT_REQUEST" } }, token:))).to eq("UNAUTHENTICATED")
      end
    end

    it "sends no email to the member (owner decision)" do
      expect { start_as(admin) }.not_to have_enqueued_job
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  describe "me { impersonation } (the banner)" do
    let(:banner) { "{ me { id impersonation { id reasonCategory reason startedAt expiresAt target { id email } } } }" }

    it "tells the frontend a session is running, who is being acted as, and when it ends" do
      body = gql(banner, token: started_token)

      expect(body.dig("data", "me", "id")).to eq(member.id)
      expect(body.dig("data", "me", "impersonation")).to include("id" => Impersonation.sole.id, "reasonCategory" => "SUPPORT_REQUEST")
      expect(body.dig("data", "me", "impersonation", "target", "id")).to eq(member.id)
      expect(Time.zone.parse(body.dig("data", "me", "impersonation", "expiresAt"))).to be_within(2.seconds).of(Impersonation.sole.expires_at)
    end

    it "is empty in a normal request, for the member and for the admin (even with a session open)" do
      started_token

      expect(gql(banner, token: token_for(member)).dig("data", "me", "impersonation")).to be_nil
      expect(gql(banner, token: token_for(admin)).dig("data", "me", "impersonation")).to be_nil
    end

    it "is empty after the session ended" do
      token = started_token
      gql(stop, token:)

      expect(error_code(gql(banner, token:))).to eq("UNAUTHENTICATED")
    end

    it "is not returned to a member who logs in while an admin impersonates them" do
      started_token

      expect(gql(banner, token: token_for(member)).dig("data", "me", "impersonation")).to be_nil
    end
  end

  describe "several admins" do
    let!(:second_admin) { create(:user, :super_admin) }

    it "may impersonate the same member at the same time, each with their own session and token" do
      first = started_token
      second = gql(start, variables: { i: { userId: member.id, reasonCategory: "BUG_INVESTIGATION" } }, token: token_for(second_admin)).dig("data", "startImpersonation", "token")

      expect(Impersonation.unended.count).to eq(2)
      expect(gql(me, token: first).dig("data", "me", "id")).to eq(member.id)
      expect(gql(me, token: second).dig("data", "me", "id")).to eq(member.id)
    end

    it "keeps one admin's session when the other admin stops theirs, and records each under its own admin" do
      first = started_token
      second = gql(start, variables: { i: { userId: member.id, reasonCategory: "BUG_INVESTIGATION" } }, token: token_for(second_admin)).dig("data", "startImpersonation", "token")

      gql(stop, token: first)
      gql("mutation($i: UpdateProfileInput!) { updateProfile(input: $i) { errors { code } } }", variables: { i: { firstName: "Ada", lastName: "King", dateOfBirth: "1990-05-21", phone: "+14155552671" } }, token: second)

      expect(error_code(gql(me, token: first))).to eq("UNAUTHENTICATED")
      expect(gql(me, token: second).dig("data", "me", "id")).to eq(member.id)
      expect(AuditVersion.where(item_id: member.id).order(:created_at, :id).last).to have_attributes(whodunnit: second_admin.id, impersonation_id: Impersonation.unended.sole.id)
    end

    it "ends both sessions when the member is archived" do
      first = started_token
      second = gql(start, variables: { i: { userId: member.id, reasonCategory: "BUG_INVESTIGATION" } }, token: token_for(second_admin)).dig("data", "startImpersonation", "token")

      Users::Archive.call(user: member)

      expect([ first, second ].map { |token| error_code(gql(me, token:)) }).to all(eq("UNAUTHENTICATED"))
      expect(Impersonation.unended.count).to eq(0)
    end
  end

  describe "stopImpersonation" do
    it "ends the session, records it as stopped, and kills the token" do
      token = started_token

      body = gql(stop, token:)

      expect(body.dig("data", "stopImpersonation")).to include("success" => true, "errors" => [])
      expect(Impersonation.sole).to have_attributes(ended_reason: "stopped")
      expect(Impersonation.sole.ended_at).to be_present
      expect(error_code(gql(me, token:))).to eq("UNAUTHENTICATED")
    end

    it "keeps the admin's own token working" do
      own = token_for(admin)
      token = started_token

      gql(stop, token:)

      expect(gql(me, token: own).dig("data", "me", "id")).to eq(admin.id)
    end

    it "lets the admin start again afterwards" do
      gql(stop, token: started_token)

      expect(start_as(admin).dig("data", "startImpersonation", "errors")).to eq([])
    end

    it "answers NOT_IMPERSONATING for a normal token, and ends nobody's session" do
      started_token

      body = gql(stop, token: token_for(admin))

      expect(body.dig("data", "stopImpersonation")).to include("success" => false)
      expect(body.dig("data", "stopImpersonation", "errors", 0, "code")).to eq("NOT_IMPERSONATING")
      expect(Impersonation.unended.count).to eq(1)
    end

    it "denies nobody logged in with UNAUTHENTICATED" do
      expect(error_code(gql(stop))).to eq("UNAUTHENTICATED")
    end

    it "can be stopped even when the member has not finished onboarding" do
      token = started_token
      stub_onboarding_steps(onboarding_step("profile", operations: %w[updateProfile])) # the member now has a step left

      expect(error_code(gql("{ somethingElse }", token:))).to eq("ONBOARDING_REQUIRED")
      expect(gql(stop, token:).dig("data", "stopImpersonation", "success")).to be(true)
    end

    it "answers UNAUTHENTICATED when the session already ran out" do
      token = started_token

      travel_to(31.minutes.from_now) { expect(error_code(gql(stop, token:))).to eq("UNAUTHENTICATED") }
    end
  end

  describe "logout while impersonating" do
    it "ends only the impersonation and keeps the admin logged in" do
      own = token_for(admin)
      token = started_token

      body = gql(logout, token:)

      expect(body.dig("data", "logout", "success")).to be(true)
      expect(Impersonation.sole.ended_reason).to eq("stopped")
      expect(error_code(gql(me, token:))).to eq("UNAUTHENTICATED")
      expect(gql(me, token: own).dig("data", "me", "id")).to eq(admin.id)
    end

    it "still ends a normal session in a normal logout, and leaves other sessions alone" do
      token = token_for(member)
      other = token_for(member)

      gql(logout, token:)

      expect(error_code(gql(me, token:))).to eq("UNAUTHENTICATED")
      expect(gql(me, token: other).dig("data", "me", "id")).to eq(member.id)
    end
  end
end
