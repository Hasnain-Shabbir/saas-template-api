require "rails_helper"

RSpec.describe Impersonations::EndAll do
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { create(:user, :super_admin) }
  let(:member) { create(:user, password: "correct horse battery") }
  let!(:started) { Impersonations::Start.call(impersonator: admin, target: member, reason_category: "support_request").value }
  let(:session) { started.impersonation }

  def revoked?(session) = User.jwt_revoked?({ "jti" => session.jti, "aud" => nil }, session.target)

  it "ends the sessions of the user as the member, and kills their tokens" do
    described_class.call(user: member)

    expect(session.reload).to have_attributes(ended_reason: "ended_by_system")
    expect(session.ended_at).to be_present
    expect(revoked?(session)).to be(true)
  end

  it "ends the sessions of the user as the admin" do
    described_class.call(user: admin)

    expect(session.reload.ended_reason).to eq("ended_by_system")
    expect(revoked?(session)).to be(true)
  end

  it "leaves the sessions of other users alone" do
    other_admin = create(:user, :super_admin)
    other = Impersonations::Start.call(impersonator: other_admin, target: create(:user), reason_category: "support_request").value.impersonation

    described_class.call(user: member)

    expect(other.reload.ended_at).to be_nil
    expect(session.reload.ended_at).to be_present
  end

  it "records a session that had already run out as expired" do
    travel_to(session.expires_at + 5.minutes) { described_class.call(user: member) }

    expect(session.reload).to have_attributes(ended_reason: "expired", ended_at: session.expires_at)
  end

  it "changes nothing for a session that already ended, and succeeds when there is nothing to end" do
    Impersonations::Stop.call(impersonation: session)
    ended_at = session.reload.ended_at

    expect(described_class.call(user: member)).to be_success
    expect(described_class.call(user: create(:user))).to be_success
    expect(session.reload).to have_attributes(ended_at:, ended_reason: "stopped")
  end

  describe "where it is called" do
    it "ends the session when the member is archived" do
      Users::Archive.call(user: member)

      expect(session.reload.ended_reason).to eq("ended_by_system")
      expect(revoked?(session)).to be(true)
    end

    it "ends the session when the member's access is revoked" do
      Users::RevokeAccess.call(user: member)

      expect(session.reload.ended_reason).to eq("ended_by_system")
    end

    it "ends the session when the member resets their password" do
      code = Auth::IssueOneTimeCode.call(user: member, purpose: :password_reset).value

      expect(Auth::ResetPassword.call(email: member.email, code:, password: "a brand new password")).to be_success

      expect(session.reload.ended_reason).to eq("ended_by_system")
    end

    it "ends the session when the admin resets their password" do
      admin.update!(password: "correct horse battery")
      Impersonations::Stop.call(impersonation: session)
      fresh = Impersonations::Start.call(impersonator: admin, target: member, reason_category: "support_request").value.impersonation
      code = Auth::IssueOneTimeCode.call(user: admin, purpose: :password_reset).value

      Auth::ResetPassword.call(email: admin.email, code:, password: "a brand new password")

      expect(fresh.reload.ended_reason).to eq("ended_by_system")
      expect(admin.allowlisted_jwts).to be_empty
    end

    it "ends the session when the member confirms an email change (their other sessions end)" do
      member.update!(pending_email: "fresh@example.test")
      code = Auth::IssueOneTimeCode.call(user: member, purpose: :email_change).value

      expect(Auth::ConfirmEmailChange.call(user: member, code:, token: Auth::IssueToken.call(member))).to be_success

      expect(session.reload.ended_reason).to eq("ended_by_system")
    end

    it "does not end the session when the reset fails (a wrong code)" do
      Auth::ResetPassword.call(email: member.email, code: "000000", password: "a brand new password")

      expect(session.reload.ended_at).to be_nil
    end
  end
end
