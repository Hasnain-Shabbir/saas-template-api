require "rails_helper"

RSpec.describe Impersonations::Start do
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { create(:user, :super_admin) }
  let(:member) { create(:user) }

  def start(impersonator: admin, target: member, reason_category: "support_request", **options)
    described_class.call(impersonator:, target:, reason_category:, **options)
  end

  describe "a valid start" do
    it "creates the session row and returns it with a token" do
      result = start(reason_category: "other", reason: "Checking a billing complaint", request_id: "req-1")

      expect(result).to be_success
      session = result.value.impersonation
      expect(session).to have_attributes(impersonator_id: admin.id, target_id: member.id, reason_category: "other",
                                         reason: "Checking a billing complaint", request_id: "req-1", ended_at: nil)
      expect(session.expires_at - session.started_at).to be_within(1.second).of(30.minutes)
    end

    it "issues a token for the target (not the admin) that the library accepts, expires in 30 minutes, and is in the allowlist" do
      result = start

      payload = Warden::JWTAuth::TokenDecoder.new.call(result.value.token)
      expect(payload["sub"]).to eq(member.id)
      expect(payload["jti"]).to eq(result.value.impersonation.jti)
      expect(payload["exp"] - payload["iat"]).to eq(30.minutes.to_i)
      expect(member.allowlisted_jwts.pluck(:jti)).to eq([ payload["jti"] ])
      expect(admin.allowlisted_jwts).to be_empty
    end

    it "leaves the admin's own tokens alone" do
      Auth::IssueToken.call(admin)

      expect { start }.not_to change { admin.allowlisted_jwts.count }
    end

    it "stops working after 30 minutes" do
      token = start.value.token

      travel_to(31.minutes.from_now) do
        expect { Warden::JWTAuth::TokenDecoder.new.call(token) }.to raise_error(JWT::ExpiredSignature)
      end
    end

    it "allows a locked member (owner decision)" do
      member.update_columns(locked_at: Time.current, failed_attempts: 5)

      expect(start).to be_success
    end

    it "accepts every category that needs no note" do
      Impersonation.reason_categories.each_key.reject { |category| category == "other" }.each do |category|
        expect(start(reason_category: category, target: create(:user), impersonator: create(:user, :super_admin))).to be_success
      end
    end
  end

  describe "who may start" do
    it "refuses a member as the impersonator" do
      result = start(impersonator: create(:user))

      expect(result).to be_failure
      expect(result.code).to eq("FORBIDDEN")
      expect(Impersonation.count).to eq(0)
    end

    it "refuses an archived or access-revoked super_admin" do
      blocked_by_archive = create(:user, :super_admin, archived_at: Time.current)
      blocked_by_revoke = create(:user, :super_admin, access_revoked_at: Time.current)

      [ blocked_by_archive, blocked_by_revoke ].each do |blocked|
        expect(start(impersonator: blocked)).to be_failure
      end
      expect(Impersonation.count).to eq(0)
    end
  end

  describe "who may be impersonated" do
    it "refuses another super_admin" do
      result = start(target: create(:user, :super_admin))

      expect(result.code).to eq("FORBIDDEN")
      expect(result.message).to eq(Errors::IMPERSONATE_SUPER_ADMIN.message)
    end

    it "refuses the admin themself" do
      expect(start(target: admin).message).to eq(Errors::IMPERSONATE_SUPER_ADMIN.message)
    end

    it "refuses an archived member and an access-revoked member" do
      [ create(:user, archived_at: Time.current), create(:user, access_revoked_at: Time.current) ].each do |blocked|
        result = start(target: blocked)

        expect(result.code).to eq("FORBIDDEN")
        expect(result.message).to eq(Errors::IMPERSONATE_BLOCKED_USER.message)
        expect(blocked.allowlisted_jwts).to be_empty
      end
      expect(Impersonation.count).to eq(0)
    end
  end

  describe "validation" do
    it "needs a note for the category other, and creates nothing" do
      result = start(reason_category: "other")

      expect(result.code).to eq("VALIDATION_FAILED")
      expect(result.errors[:reason]).to be_present
      expect(Impersonation.count).to eq(0)
      expect(member.allowlisted_jwts).to be_empty
    end

    it "refuses an unknown or empty category, and a too long note" do
      expect(start(reason_category: "fun").code).to eq("VALIDATION_FAILED")
      expect(start(reason_category: nil).code).to eq("VALIDATION_FAILED")
      expect(start(reason: "a" * (ValidationRules::IMPERSONATION_REASON_MAX_LENGTH + 1)).code).to eq("VALIDATION_FAILED")
      expect(Impersonation.count).to eq(0)
    end
  end

  describe "one open session per admin" do
    it "ends the first session and kills its token when the admin starts another (for example on a second device)" do
      first = start.value
      other_member = create(:user)

      result = start(target: other_member)

      expect(result).to be_success
      expect(first.impersonation.reload).to have_attributes(ended_reason: "ended_by_system")
      expect(first.impersonation.ended_at).to be_present
      expect(User.jwt_revoked?({ "jti" => first.impersonation.jti, "aud" => nil }, member)).to be(true)
      expect(Impersonation.unended.pluck(:target_id)).to eq([ other_member.id ])
      expect(other_member.allowlisted_jwts.count).to eq(1)
    end

    it "keeps the admin's own logins when it replaces a session" do
      Auth::IssueToken.call(admin)
      Auth::IssueToken.call(admin) # a second device
      start

      expect { start(target: create(:user)) }.not_to change { admin.allowlisted_jwts.count }
    end

    it "records a session that ran out as expired, ending at its expiry, then starts the new one" do
      first = start.value.impersonation

      travel_to(first.expires_at + 5.minutes) do
        result = start(target: create(:user))

        expect(result).to be_success
        expect(first.reload).to have_attributes(ended_reason: "expired", ended_at: first.expires_at)
        expect(AllowlistedJwt.where(jti: first.jti)).to be_empty
      end
    end

    it "allows a new start after the admin stopped the first" do
      Impersonations::Stop.call(impersonation: start.value.impersonation)

      expect(start).to be_success
    end

    it "lets two different admins impersonate at the same time" do
      start
      other_admin = create(:user, :super_admin)

      expect(start(impersonator: other_admin, target: create(:user))).to be_success
    end

    it "answers the same way, and keeps nothing, when the database catches a start at the same time" do
      allow(Impersonations::IssueToken).to receive(:call).and_raise(ActiveRecord::RecordNotUnique)

      expect(start.code).to eq("IMPERSONATION_ACTIVE")
      expect(Impersonation.count).to eq(0)
    end
  end
end
