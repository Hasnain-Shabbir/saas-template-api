require "rails_helper"

RSpec.describe Invitation do
  it "has the same roles as users" do
    expect(described_class.roles.keys).to match_array(User.roles.keys)
  end

  it "normalizes the email and checks its format and length" do
    expect(build(:invitation, email: "  Person@Example.TEST ").tap(&:valid?).email).to eq("person@example.test")
    expect(build(:invitation, email: "not-an-email")).not_to be_valid
    expect(build(:invitation, email: "#{'a' * 250}@example.test")).not_to be_valid
  end

  it "rejects an unknown role" do
    expect(build(:invitation, role: "owner")).not_to be_valid
  end

  describe ".digest" do
    it "is a keyed digest that never contains the token" do
      digest = described_class.digest("abc")

      expect(digest).to match(/\A\h{64}\z/)
      expect(digest).not_to eq(Digest::SHA256.hexdigest("abc"))
      expect(digest).to eq(described_class.digest("abc"))
    end
  end

  describe ".generate_token" do
    it "matches the format in ValidationRules and does not repeat" do
      tokens = Array.new(5) { described_class.generate_token }

      expect(tokens).to all(match(ValidationRules::INVITATION_TOKEN_FORMAT))
      expect(tokens.uniq.size).to eq(5)
    end
  end

  describe "state" do
    include ActiveSupport::Testing::TimeHelpers

    it "is usable while open and not expired" do
      invitation = create(:invitation)
      expect(invitation).to be_usable

      travel_to(Invitation::LIFETIME.from_now + 1.second) { expect(invitation).to be_expired }
      expect(build(:invitation, accepted_at: Time.current)).not_to be_usable
      expect(build(:invitation, revoked_at: Time.current)).not_to be_usable
    end
  end

  describe "database constraints" do
    it "allows one open invitation per email, but not a second" do
      create(:invitation, email: "same@example.test")

      expect { create(:invitation, email: "same@example.test") }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows a new invitation once the earlier one was used or revoked" do
      create(:invitation, email: "same@example.test", revoked_at: Time.current)
      create(:invitation, email: "same@example.test", accepted_at: Time.current)

      expect { create(:invitation, email: "same@example.test") }.not_to raise_error
    end

    it "refuses an invitation that is both accepted and revoked" do
      invitation = build(:invitation, accepted_at: Time.current, revoked_at: Time.current)

      expect { invitation.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /invitations_accepted_or_revoked/)
    end

    it "refuses an unknown role even without validations" do
      expect { build(:invitation, role: "owner").save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /invitations_role_values/)
    end

    it "keeps the invitation when the inviter is deleted" do
      inviter = create(:user, :super_admin)
      invitation = create(:invitation, inviter:)

      inviter.destroy!

      expect(invitation.reload.inviter_id).to be_nil
    end
  end
end
