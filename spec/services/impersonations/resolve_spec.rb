require "rails_helper"

RSpec.describe Impersonations::Resolve do
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { create(:user, :super_admin) }
  let(:member) { create(:user) }
  let(:started) { Impersonations::Start.call(impersonator: admin, target: member, reason_category: "support_request").value }

  def resolve(user: member, token: started.token) = described_class.call(user:, token:)

  it "returns nil for a normal login token" do
    result = resolve(token: Auth::IssueToken.call(member))

    expect(result).to be_success
    expect(result.value).to be_nil
  end

  it "returns the session for the token of an open session" do
    result = resolve

    expect(result).to be_success
    expect(result.value).to eq(started.impersonation)
    expect(result.value.impersonator).to eq(admin)
  end

  it "does not take the admin's own login token for an impersonation" do
    started

    expect(resolve(user: admin, token: Auth::IssueToken.call(admin)).value).to be_nil
  end

  describe "fails closed" do
    it "refuses a token whose session ended, even when its allowlist row is still there" do
      token = started.token
      Impersonations::Stop.call(impersonation: started.impersonation)
      member.allowlisted_jwts.create!(jti: started.impersonation.jti, exp: 30.minutes.from_now) # a leftover row

      result = resolve(token:)

      expect(result).to be_failure
      expect(result.code).to eq("UNAUTHENTICATED")
    end

    it "refuses a token that runs past its session (the signed expiry)" do
      token = started.token

      travel_to(31.minutes.from_now) { expect(resolve(token:).code).to eq("UNAUTHENTICATED") }
    end

    it "refuses a session whose row ran out although the token still verifies" do
      token = started.token
      started.impersonation.update_columns(expires_at: 1.minute.ago, started_at: 31.minutes.ago)

      expect(resolve(token:).code).to eq("UNAUTHENTICATED")
    end

    it "refuses when the admin was archived or access-revoked after the start" do
      token = started.token

      admin.update!(archived_at: Time.current)
      expect(resolve(token:).code).to eq("UNAUTHENTICATED")

      admin.update!(archived_at: nil, access_revoked_at: Time.current)
      expect(resolve(token:).code).to eq("UNAUTHENTICATED")
    end

    it "refuses when the admin is locked" do
      token = started.token
      admin.update_columns(locked_at: Time.current)

      expect(resolve(token:).code).to eq("UNAUTHENTICATED")
    end

    it "refuses when the admin is no longer a super_admin" do
      token = started.token
      admin.update!(role: "member")

      expect(resolve(token:).code).to eq("UNAUTHENTICATED")
    end

    it "refuses a session used by a user who is not its target" do
      expect(resolve(user: create(:user)).code).to eq("UNAUTHENTICATED")
    end

    it "refuses a garbage token, a missing token, and a token signed with another key" do
      forged = JWT.encode({ "sub" => member.id, "jti" => started.impersonation.jti, "exp" => 10.minutes.from_now.to_i }, "not the secret", "HS256")

      [ "garbage", nil, forged ].each do |token|
        expect(resolve(token:).code).to eq("UNAUTHENTICATED")
      end
    end
  end
end
