require "rails_helper"

RSpec.describe Auth::Login do
  before { allow(BCrypt::Engine).to receive(:hash_secret).and_call_original }

  # Same work for every failure, so response time does not tell an attacker which emails have accounts.
  it "runs bcrypt for an unknown email" do
    described_class.call(email: "nobody@example.test", password: "some password 1")

    expect(BCrypt::Engine).to have_received(:hash_secret).once
  end

  it "runs bcrypt for a locked account" do
    user = create(:user, password: "correct horse battery")
    Devise.maximum_attempts.times { described_class.call(email: user.email, password: "wrong password 1") }
    RSpec::Mocks.space.proxy_for(BCrypt::Engine).reset
    allow(BCrypt::Engine).to receive(:hash_secret).and_call_original

    result = described_class.call(email: user.email, password: "correct horse battery")

    expect(result).to be_failure
    expect(BCrypt::Engine).to have_received(:hash_secret).once
  end

  it "fails with INVALID_CREDENTIALS and no token for each failure kind" do
    user = create(:user, password: "correct horse battery")

    results = [ described_class.call(email: user.email, password: "wrong password 1"),
                described_class.call(email: "nobody@example.test", password: "wrong password 1") ]

    expect(results.map(&:code)).to all(eq("INVALID_CREDENTIALS"))
    expect(results.map(&:value)).to all(be_nil)
  end
end
