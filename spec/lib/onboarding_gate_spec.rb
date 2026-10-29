require "rails_helper"

RSpec.describe OnboardingGate do
  let(:user) { create(:user) }

  def blocked?(query, operation_name: nil, as: user) = described_class.blocked?(as, query, operation_name:)

  context "when the role has no steps" do
    it "never blocks" do
      expect(blocked?("mutation { inviteUser(input: {}) { success } }")).to be(false)
      expect(blocked?("{ somethingUnknown }")).to be(false)
    end
  end

  context "with steps" do
    before { stub_onboarding_steps(onboarding_step("profile", operations: %w[updateProfile]), onboarding_step("terms")) }

    it "blocks any operation that is not open" do
      expect(blocked?("mutation { inviteUser(input: {}) { success } }")).to be(true)
      expect(blocked?("mutation { requestEmailChange(input: {}) { success } }")).to be(true)
      expect(blocked?("{ somethingUnknown }")).to be(true)
    end

    it "lets through the operations that finish onboarding, and logout" do
      expect(blocked?("{ me { id } }")).to be(false)
      expect(blocked?("{ me { onboarding { completed } } }")).to be(false)
      expect(blocked?("mutation { logout(input: {}) { success } }")).to be(false)
      expect(blocked?("{ __typename }")).to be(false)
    end

    it "lets through the operations a step lists, and public operations" do
      expect(blocked?("mutation { updateProfile(input: {}) { success } }")).to be(false)
      expect(blocked?("mutation { requestPasswordReset(input: {}) { success } }")).to be(false)
    end

    it "does not open the operations of a step of another role" do
      stub_onboarding_steps(onboarding_step("profile"), onboarding_step("billing", roles: %w[super_admin], operations: %w[updateBilling]))

      expect(blocked?("mutation { updateBilling(input: {}) { success } }")).to be(true)
      expect(blocked?("mutation { updateBilling(input: {}) { success } }", as: create(:user, :super_admin))).to be(false)
    end

    it "blocks when one root field is not open, whatever hides it" do
      expect(blocked?("{ me { id } inviteUser2: somethingElse }")).to be(true)
      expect(blocked?("{ mine: inviteUser { id } }")).to be(true)
      expect(blocked?("{ ...F } fragment F on Query { somethingElse }")).to be(true)
      expect(blocked?("{ ... on Query { somethingElse } }")).to be(true)
      expect(blocked?("{ me: somethingElse }")).to be(true) # an alias cannot borrow the name of an open field
    end

    it "looks only at the operation that runs" do
      query = "query A { me { id } } query B { somethingElse }"

      expect(blocked?(query, operation_name: "A")).to be(false)
      expect(blocked?(query, operation_name: "B")).to be(true)
    end

    it "leaves a query that cannot be parsed to GraphQL" do
      expect(blocked?("mutation {")).to be(false)
    end

    it "stops blocking when the last step is done" do
      user.onboarding_steps.create!(step_key: "profile", completed_at: Time.current)
      expect(blocked?("{ somethingElse }")).to be(true)

      user.onboarding_steps.create!(step_key: "terms", completed_at: Time.current)
      expect(blocked?("{ somethingElse }")).to be(false)
    end

    it "does not block a role that has no steps" do
      stub_onboarding_steps(onboarding_step("profile", roles: %w[member]))

      expect(blocked?("{ somethingElse }", as: create(:user, :super_admin))).to be(false)
      expect(blocked?("{ somethingElse }", as: create(:user, :member))).to be(true)
    end
  end
end
