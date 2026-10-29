require "rails_helper"

RSpec.describe Terms::Accept do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  def accept(version = Terms::Current::VERSION) = described_class.call(user:, version:)

  it "records the current version and the time, and returns the user" do
    result = freeze_time { accept }

    expect(result).to be_success
    expect(result.value).to eq(user)
    expect(user.reload).to have_attributes(terms_version: Terms::Current::VERSION, terms_accepted_at: be_within(1.second).of(Time.current))
    expect(user.terms_accepted?).to be(true)
  end

  it "accepts the version with spaces around it" do
    expect(accept("  #{Terms::Current::VERSION} ")).to be_success
  end

  it "does nothing when accepted again: the first time stays" do
    accept
    stamp = user.reload.terms_accepted_at

    result = travel_to(1.day.from_now) { accept }

    expect(result).to be_success
    expect(user.reload.terms_accepted_at).to eq(stamp)
  end

  describe "a wrong version" do
    it "is refused and nothing is saved" do
      [ "1999-01-01", "2026-10-01 extra", "' OR 1=1 --", "x" * 5000 ].each do |version|
        result = accept(version)

        expect(result.code).to eq("VALIDATION_FAILED")
        expect(result.errors.map(&:full_message)).to eq([ "Version must be the current version of the terms. Reload the terms and accept again" ])
        expect(result.errors.first.attribute).to eq(:version)
      end
      expect(user.reload).to have_attributes(terms_version: nil, terms_accepted_at: nil)
    end

    it "says an empty version is required, not invalid" do
      [ "", "   ", nil ].each do |version|
        expect(accept(version).errors.map(&:full_message)).to eq([ "Version is required" ])
      end
    end

    it "never repeats the value that was sent" do
      expect(accept("secret-value-9").errors.map(&:full_message).join).not_to include("secret-value-9")
    end
  end

  it "finishes the terms step once the earlier steps are done" do
    stub_onboarding_steps(*real_onboarding_steps)
    user.update!(first_name: "Ada", last_name: "Lovelace", date_of_birth: Date.new(1990, 5, 21), phone: "+14155552671",
                 address_line_1: "1 Market Street", city: "San Francisco", state: "CA", postal_code: "94105", country: "US")
    Onboarding::Sync.call(user:)

    accept

    expect(user.onboarding_steps.pluck(:step_key)).to contain_exactly("profile", "address", "terms")
  end

  it "touches only the user it is given" do
    other = create(:user)
    accept

    expect(other.reload).to have_attributes(terms_version: nil, terms_accepted_at: nil)
  end
end
