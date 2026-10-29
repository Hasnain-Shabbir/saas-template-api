require "rails_helper"

RSpec.describe InvitationPolicy do
  let(:invitation) { build(:invitation) }

  describe "as a super_admin" do
    let(:user) { create(:user, :super_admin) }

    it "may invite a member" do
      expect(described_class.new(user, build(:invitation, role: "member")).create?).to be(true)
    end

    it "may not invite a super_admin" do
      expect(described_class.new(user, build(:invitation, role: "super_admin")).create?).to be(false)
    end

    it "may revoke and resend" do
      expect(described_class.new(user, Invitation).revoke?).to be(true)
      expect(described_class.new(user, Invitation).resend?).to be(true)
    end

    it "may grant the member role only" do
      expect(described_class.new(user, invitation).grantable_roles).to eq([ "member" ])
    end
  end

  describe "as a member" do
    let(:user) { create(:user) }

    it "may do nothing, for any role" do
      User.roles.each_key do |role|
        expect(described_class.new(user, build(:invitation, role:)).create?).to be(false)
      end
      expect([ :revoke?, :resend?, :index?, :show?, :update?, :destroy? ].map { |action| described_class.new(user, Invitation).public_send(action) }).to all(be(false))
    end

    it "may grant no role" do
      expect(described_class.new(user, invitation).grantable_roles).to eq([])
    end
  end

  it "denies everything when nobody is logged in" do
    policy = described_class.new(nil, invitation)

    expect([ :create?, :revoke?, :resend?, :index?, :show?, :update?, :destroy? ].map { |action| policy.public_send(action) }).to all(be(false))
    expect(policy.grantable_roles).to eq([])
  end
end
