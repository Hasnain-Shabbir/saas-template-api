require "rails_helper"

RSpec.describe Onboarding::Registry do
  # The checks every step a project adds must pass. They run on the real list, so a bad step fails here and not in production.
  describe "the steps in the registry" do
    let(:steps) { real_onboarding_steps }

    it "has unique keys" do
      expect(steps.map(&:key)).to eq(steps.map(&:key).uniq)
    end

    it "has keys in the allowed format and length" do
      expect(steps.map(&:key)).to all(match(ValidationRules::ONBOARDING_STEP_KEY_FORMAT))
      expect(steps.map { |step| step.key.length }).to all(be <= ValidationRules::ONBOARDING_STEP_KEY_MAX_LENGTH)
    end

    it "only names roles that exist" do
      expect(steps.filter_map(&:roles).flatten - User.roles.keys).to be_empty
    end

    it "has a condition that can be called, and operations that are names" do
      expect(steps.map(&:complete_when)).to all(respond_to(:call))
      expect(steps.flat_map(&:operations)).to all(match(/\A[a-z][A-Za-z0-9]*\z/))
    end

    it "gives members a profile step that needs the whole profile, and super_admin none" do
      profile = steps.find { |step| step.key == "profile" }

      expect(profile.roles).to eq(%w[member])
      expect(profile.operations).to eq(%w[updateProfile])
      expect(profile.satisfied_by?(build(:user))).to be(false)
      expect(profile.satisfied_by?(build(:user, :with_profile))).to be(true)
    end

    it "gives members an address step that needs the address, and super_admin none" do
      address = steps.find { |step| step.key == "address" }

      expect(address.roles).to eq(%w[member])
      expect(address.operations).to eq(%w[updateAddress])
      expect(steps.map(&:key)).to eq(%w[profile address terms])
      expect(address.satisfied_by?(build(:user))).to be(false)
      expect(address.satisfied_by?(build(:user, :with_address))).to be(true)
    end

    it "gives members a terms step that needs the current version, and super_admin none" do
      terms = steps.find { |step| step.key == "terms" }

      expect(terms.roles).to eq(%w[member])
      expect(terms.operations).to eq(%w[acceptTerms])
      expect(terms.satisfied_by?(build(:user))).to be(false)
      expect(terms.satisfied_by?(build(:user, :with_terms))).to be(true)
      expect(terms.satisfied_by?(build(:user, terms_version: "1999-01-01", terms_accepted_at: Time.current))).to be(false)
    end

    it "keeps the database limit in step with the rule" do
      limit = OnboardingStep.connection.check_constraints(:onboarding_steps).find { |c| c.name == "onboarding_steps_step_key_length" }

      expect(limit.expression).to include(ValidationRules::ONBOARDING_STEP_KEY_MAX_LENGTH.to_s)
    end
  end

  describe ".steps_for" do
    let(:member) { build(:user, :member) }
    let(:admin) { build(:user, :super_admin) }

    before do
      stub_onboarding_steps(onboarding_step("profile"), onboarding_step("billing", roles: %w[super_admin]), onboarding_step("terms", roles: [ :member ]))
    end

    it "returns the steps of the role, in order" do
      expect(described_class.steps_for(member).map(&:key)).to eq(%w[profile terms])
      expect(described_class.steps_for(admin).map(&:key)).to eq(%w[profile billing])
    end

    it "returns every step for a step without roles" do
      expect(described_class.steps_for(member).map(&:key)).to include("profile")
      expect(described_class.steps_for(admin).map(&:key)).to include("profile")
    end
  end

  describe Onboarding::Step do
    it "counts a condition as met only for a literal true" do
      user = build(:user)

      expect(described_class.new(key: "a", complete_when: ->(_user) { true }).satisfied_by?(user)).to be(true)
      expect(described_class.new(key: "a", complete_when: ->(_user) { "yes" }).satisfied_by?(user)).to be(false)
      expect(described_class.new(key: "a", complete_when: ->(_user) { nil }).satisfied_by?(user)).to be(false)
    end

    it "has no condition and no operations by default" do
      step = described_class.new(key: "a")

      expect(step.satisfied_by?(build(:user))).to be(true)
      expect(step.operations).to eq([])
      expect(step.roles).to be_nil
    end
  end
end
