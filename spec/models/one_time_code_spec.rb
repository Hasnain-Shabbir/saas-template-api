require "rails_helper"

RSpec.describe OneTimeCode do
  let(:user) { create(:user) }
  let(:attributes) do
    { user_id: user.id, purpose: "password_reset", code_digest: "digest", expires_at: 10.minutes.from_now,
      created_at: Time.current, updated_at: Time.current }
  end

  it "needs a user, a purpose, a digest, and an expiry" do
    record = described_class.new

    expect(record).not_to be_valid
    expect(record.errors.attribute_names).to include(:user, :purpose, :code_digest, :expires_at)
  end

  it "refuses a purpose that is not in the list" do
    expect(described_class.new(user:, purpose: "other", code_digest: "x", expires_at: 1.minute.from_now)).not_to be_valid
  end

  it "enforces one code per user and purpose in the database" do
    described_class.insert_all!([ attributes ])

    expect { described_class.insert_all!([ attributes ]) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "accepts the email_change purpose, one code per purpose for the same user" do
    described_class.insert_all!([ attributes, attributes.merge(purpose: "email_change") ])

    expect(described_class.where(user_id: user.id).pluck(:purpose)).to match_array(%w[password_reset email_change])
  end

  it "enforces the purpose list and a non-negative attempt count in the database" do
    expect { described_class.insert_all!([ attributes.merge(purpose: "other") ]) }.to raise_error(ActiveRecord::StatementInvalid)
    expect { described_class.insert_all!([ attributes.merge(attempts: -1) ]) }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "is deleted with its user" do
    described_class.insert_all!([ attributes ])

    expect { user.destroy! }.to change(described_class, :count).by(-1)
  end

  describe ".digest" do
    it "is a keyed HMAC, not a plain hash of the code" do
      digest = described_class.digest(user_id: user.id, purpose: "password_reset", code: "123456")

      expect(digest).to match(/\A\h{64}\z/)
      expect(digest).not_to eq(Digest::SHA256.hexdigest("123456"))
      expect(digest).not_to eq(Digest::SHA256.hexdigest("#{user.id}:password_reset:123456"))
    end

    it "gives the same digits a different digest for each user" do
      first = described_class.digest(user_id: user.id, purpose: "password_reset", code: "123456")
      second = described_class.digest(user_id: create(:user).id, purpose: "password_reset", code: "123456")

      expect(first).not_to eq(second)
    end

    it "is the same for the same input" do
      expect(described_class.digest(user_id: user.id, purpose: :password_reset, code: "123456"))
        .to eq(described_class.digest(user_id: user.id, purpose: "password_reset", code: "123456"))
    end
  end
end
