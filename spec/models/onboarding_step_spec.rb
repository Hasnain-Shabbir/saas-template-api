require "rails_helper"

RSpec.describe OnboardingStep do
  let(:user) { create(:user) }

  def build_step(**attributes) = described_class.new({ user:, step_key: "profile", completed_at: Time.current }.merge(attributes))

  it "is valid with a user, a key and a time" do
    expect(build_step).to be_valid
  end

  it "needs a key in the allowed format and length" do
    expect(build_step(step_key: nil)).not_to be_valid
    expect(build_step(step_key: "Profile")).not_to be_valid
    expect(build_step(step_key: "1profile")).not_to be_valid
    expect(build_step(step_key: "a" * (ValidationRules::ONBOARDING_STEP_KEY_MAX_LENGTH + 1))).not_to be_valid
    expect(build_step(step_key: "a" * ValidationRules::ONBOARDING_STEP_KEY_MAX_LENGTH)).to be_valid
  end

  it "needs a completion time" do
    expect(build_step(completed_at: nil)).not_to be_valid
  end

  it "allows a step once per user, and the same step for another user" do
    build_step.save!

    expect(build_step).not_to be_valid
    expect(build_step(user: create(:user))).to be_valid
  end

  describe "the database, when a validation is skipped" do
    it "refuses a second row for the same user and step" do
      build_step.save!

      expect { build_step.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "refuses a key over the length limit" do
      expect { build_step(step_key: "a" * (ValidationRules::ONBOARDING_STEP_KEY_MAX_LENGTH + 1)).save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /onboarding_steps_step_key_length/)
    end

    it "refuses a row without a user, or with a user that does not exist" do
      expect { build_step(user: nil).save!(validate: false) }.to raise_error(ActiveRecord::NotNullViolation)
      expect { build_step(user: nil, user_id: SecureRandom.uuid).save!(validate: false) }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  it "is deleted with its user" do
    build_step.save!

    expect { user.destroy! }.to change(described_class, :count).by(-1)
  end
end
