require "rails_helper"

RSpec.describe Impersonations::Stop do
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { create(:user, :super_admin) }
  let(:member) { create(:user) }
  let(:started) { Impersonations::Start.call(impersonator: admin, target: member, reason_category: "support_request").value }
  let(:session) { started.impersonation }

  it "ends the session as stopped, now, and kills its token" do
    started
    result = nil

    freeze_time do
      result = described_class.call(impersonation: session)

      expect(session.reload).to have_attributes(ended_reason: "stopped", ended_at: Time.current)
    end
    expect(result).to be_success
    expect(AllowlistedJwt.where(jti: session.jti)).to be_empty
    expect(Warden::JWTAuth::TokenDecoder.new.call(started.token)["jti"]).to eq(session.jti) # still a valid signature, but no longer allowlisted
    expect(User.jwt_revoked?({ "jti" => session.jti, "aud" => nil }, member)).to be(true)
  end

  it "keeps the member's other tokens and the admin's own tokens" do
    started
    Auth::IssueToken.call(member)
    Auth::IssueToken.call(admin)

    expect { described_class.call(impersonation: session) }.to change { AllowlistedJwt.count }.from(3).to(2)
    expect(member.allowlisted_jwts.count).to eq(1)
    expect(admin.allowlisted_jwts.count).to eq(1)
  end

  it "records ended_by_system when the system ends it" do
    described_class.call(impersonation: session, ended_reason: "ended_by_system")

    expect(session.reload.ended_reason).to eq("ended_by_system")
  end

  it "records a session that ran out as expired, ending at its expiry, whatever the caller says" do
    session

    travel_to(session.expires_at + 10.minutes) do
      described_class.call(impersonation: session)

      expect(session.reload).to have_attributes(ended_reason: "expired", ended_at: session.expires_at)
    end
  end

  it "changes nothing and succeeds when the session already ended" do
    described_class.call(impersonation: session)
    first_end = session.reload.ended_at

    travel_to(1.minute.from_now) do
      result = described_class.call(impersonation: session, ended_reason: "ended_by_system")

      expect(result).to be_success
      expect(session.reload).to have_attributes(ended_at: first_end, ended_reason: "stopped")
    end
  end

  it "lets the admin start a new session afterwards" do
    described_class.call(impersonation: session)

    expect(Impersonations::Start.call(impersonator: admin, target: member, reason_category: "support_request")).to be_success
  end
end
