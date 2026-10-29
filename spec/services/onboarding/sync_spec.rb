require "rails_helper"

RSpec.describe Onboarding::Sync do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:flags) { { profile: true, address: true } }

  before do
    state = flags
    stub_onboarding_steps(
      onboarding_step("profile", complete_when: ->(_user) { state[:profile] }),
      onboarding_step("address", complete_when: ->(_user) { state[:address] }),
      onboarding_step("billing", roles: %w[super_admin])
    )
  end

  def keys = user.onboarding_steps.order(:completed_at, :id).pluck(:step_key)

  it "finishes every step whose condition is met, in order, and returns the progress" do
    progress = described_class.call(user:).value

    expect(keys).to eq(%w[profile address])
    expect(progress).to have_attributes(completed: true, current_step: nil)
  end

  it "stops at the first step that is not met" do
    flags[:profile] = false

    progress = described_class.call(user:).value

    expect(keys).to be_empty
    expect(progress.current_step).to eq("profile")
  end

  it "does not skip over an open step, even when a later one is met" do
    flags[:profile] = false

    described_class.call(user:)

    expect(user.onboarding_steps.where(step_key: "address")).to be_empty
  end

  it "finishes the later step once the earlier one is met" do
    flags[:profile] = false
    described_class.call(user:)
    flags[:profile] = true

    described_class.call(user:)

    expect(keys).to eq(%w[profile address])
  end

  it "is idempotent: a second call keeps the first completed_at" do
    described_class.call(user:)
    stamp = user.onboarding_steps.find_by(step_key: "profile").completed_at

    travel_to(1.day.from_now) { described_class.call(user:) }

    expect(user.onboarding_steps.count).to eq(2)
    expect(user.onboarding_steps.find_by(step_key: "profile").completed_at).to eq(stamp)
  end

  it "never creates a step of another role" do
    described_class.call(user:)

    expect(user.onboarding_steps.where(step_key: "billing")).to be_empty
  end
end
