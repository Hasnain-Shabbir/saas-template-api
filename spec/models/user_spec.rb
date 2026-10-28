require "rails_helper"

RSpec.describe User do
  it "has a valid factory" do
    expect(build(:user)).to be_valid
  end

  it "requires an email and a password" do
    user = described_class.new

    expect(user).not_to be_valid
    expect(user.errors.attribute_names).to include(:email, :password)
  end

  it "normalizes the email" do
    user = create(:user, email: "  Mixed@Example.TEST ")

    expect(user.email).to eq("mixed@example.test")
  end

  it "rejects a duplicate email regardless of case" do
    create(:user, email: "same@example.test")

    expect(build(:user, email: "SAME@example.test")).not_to be_valid
  end

  it "enforces a unique email in the database" do
    create(:user, email: "same@example.test")
    now = Time.current
    row = { email: "same@example.test", encrypted_password: "x", created_at: now, updated_at: now }

    expect { described_class.insert_all!([ row ]) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "stores the password hashed" do
    user = create(:user, password: "correct horse battery")

    expect(user.encrypted_password).not_to include("correct horse battery")
  end

  describe "tokens" do
    let(:user) { create(:user) }

    before { 2.times { |i| user.allowlisted_jwts.create!(jti: "jti-#{i}", exp: 1.hour.from_now) } }

    it "are deleted when the password changes" do
      expect { user.update!(password: "another long password") }
        .to change { user.allowlisted_jwts.count }.from(2).to(0)
    end

    it "are kept when something else changes" do
      expect { user.update!(email: "new@example.test") }
        .not_to change { user.allowlisted_jwts.count }
    end

    it "are deleted with the user" do
      expect { user.destroy! }.to change(AllowlistedJwt, :count).by(-2)
    end
  end
end
