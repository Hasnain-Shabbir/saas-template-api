require "rails_helper"

RSpec.describe Auth::VerifyLogin do
  let!(:user) { create(:user, password: "correct horse battery") }
  let(:code) { Auth::IssueOneTimeCode.call(user:, purpose: :login).value }

  def wrong_code = code == "000000" ? "111111" : "000000"

  it "gives the user and an allowlisted token for the right code, and uses the code up" do
    result = described_class.call(email: user.email, code:)

    expect(result).to be_success
    expect(result.value[:user]).to eq(user)
    expect(user.allowlisted_jwts.count).to eq(1)
    expect(OneTimeCode.where(user_id: user.id, purpose: "login")).to be_empty
  end

  it "resets the failed attempts after a verified code" do
    user.update_columns(failed_attempts: 3)

    described_class.call(email: user.email, code:)

    expect(user.reload.failed_attempts).to eq(0)
  end

  it "fails with INVALID_CODE and no token for each failure kind" do
    code # issued
    expired = create(:user).tap { |other| Auth::IssueOneTimeCode.call(user: other, purpose: :login) }
    OneTimeCode.where(user_id: expired.id).update_all(expires_at: 1.minute.ago)

    results = [ described_class.call(email: user.email, code: wrong_code),
                described_class.call(email: user.email, code: "12ab56"),
                described_class.call(email: user.email, code: nil),
                described_class.call(email: "nobody@example.test", code:),
                described_class.call(email: expired.email, code: "123456"),
                described_class.call(email: create(:user).email, code: "123456") ]

    expect(results.map(&:code)).to all(eq("INVALID_CODE"))
    expect(results.map(&:value)).to all(be_nil)
    expect(user.allowlisted_jwts).to be_empty
  end

  it "does not use a password reset code" do
    reset = Auth::IssueOneTimeCode.call(user:, purpose: :password_reset).value

    expect(described_class.call(email: user.email, code: reset)).to be_failure
  end

  it "refuses a locked account and leaves its code alone" do
    code
    user.lock_access!

    result = described_class.call(email: user.email, code:)

    expect(result.code).to eq("INVALID_CODE")
    expect(OneTimeCode.where(user_id: user.id, purpose: "login").count).to eq(1)
  end

  it "counts a failed login only when the code is used up" do
    code
    (OneTimeCode::MAX_ATTEMPTS - 1).times { described_class.call(email: user.email, code: wrong_code) }
    expect(user.reload.failed_attempts).to eq(0)

    described_class.call(email: user.email, code: wrong_code)

    expect(user.reload.failed_attempts).to eq(1)
    expect(OneTimeCode.where(user_id: user.id)).to be_empty
  end

  it "locks the account when the used-up codes reach the Devise limit" do
    user.update_columns(failed_attempts: Devise.maximum_attempts - 1)
    code

    OneTimeCode::MAX_ATTEMPTS.times { described_class.call(email: user.email, code: wrong_code) }

    expect(user.reload.access_locked?).to be(true)
  end

  it "counts nothing when no code exists, so someone without a password cannot lock the account" do
    (Devise.maximum_attempts + 1).times { described_class.call(email: user.email, code: "123456") }

    expect(user.reload.failed_attempts).to eq(0)
    expect(user.access_locked?).to be(false)
  end
end
