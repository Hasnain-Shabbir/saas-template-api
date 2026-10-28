require "rails_helper"

RSpec.describe User do
  include ActiveSupport::Testing::TimeHelpers

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

  describe "email rules" do
    it "accepts a normal address and a plus alias" do
      expect(build(:user, email: "first.last+tag@sub.example.test")).to be_valid
    end

    [ "a@b", "plainstring", "@example.test", "a b@example.test", "<script>alert(1)</script>@x.test",
      "${7*7}@x.test", "x@y.test\r\nBcc: evil@x.test", "name\u200b@example.test", "n\u0430me@example.test" ].each do |email|
      it "rejects #{email.inspect}" do
        expect(build(:user, email:)).not_to be_valid
      end
    end

    it "rejects an email longer than #{ValidationRules::EMAIL_MAX_LENGTH} characters" do
      long = "#{'a' * ValidationRules::EMAIL_MAX_LENGTH}@example.test"

      expect(build(:user, email: long)).not_to be_valid
    end

    it "enforces the length in the database too" do
      now = Time.current
      row = { email: "#{'a' * 260}@example.test", encrypted_password: "x", created_at: now, updated_at: now }

      expect { described_class.insert_all!([ row ]) }.to raise_error(ActiveRecord::StatementInvalid, /users_email_length/)
    end
  end

  describe "password rules" do
    it "needs at least #{ValidationRules::PASSWORD_MIN_LENGTH} characters" do
      expect(build(:user, password: "a" * (ValidationRules::PASSWORD_MIN_LENGTH - 1))).not_to be_valid
      expect(build(:user, password: "a" * ValidationRules::PASSWORD_MIN_LENGTH)).to be_valid
    end

    it "allows at most #{ValidationRules::PASSWORD_MAX_BYTES} bytes" do
      expect(build(:user, password: "a" * ValidationRules::PASSWORD_MAX_BYTES)).to be_valid
      expect(build(:user, password: "a" * (ValidationRules::PASSWORD_MAX_BYTES + 1))).not_to be_valid
    end

    it "counts bytes, not characters (bcrypt cuts at bytes)" do
      emoji_password = "🔥" * 19 # 19 characters, 76 bytes

      expect(build(:user, password: emoji_password)).not_to be_valid
    end
  end

  describe "role" do
    it "defaults to member" do
      expect(described_class.new.role).to eq("member")
      expect(create(:user)).to be_member
    end

    it "knows exactly super_admin and member" do
      expect(described_class.roles.keys).to eq(%w[super_admin member])
    end

    it "stores the role as a string" do
      user = create(:user, :super_admin)

      expect(described_class.connection.select_value("SELECT role FROM users WHERE id = '#{user.id}'")).to eq("super_admin")
    end

    it "rejects an unknown role with a validation error, not an exception" do
      user = build(:user, role: "owner")

      expect(user).not_to be_valid
      expect(user.errors.attribute_names).to include(:role)
    end

    it "refuses an unknown role in the database too" do
      user = create(:user)

      expect { user.update_column(:role, "owner") }.to raise_error(ActiveRecord::StatementInvalid, /users_role_values/)
    end

    it "refuses a null role in the database" do
      user = create(:user)

      expect { user.update_column(:role, nil) }.to raise_error(ActiveRecord::NotNullViolation)
    end
  end

  describe "locking" do
    let(:user) { create(:user) }

    it "locks after #{Devise.maximum_attempts} failed attempts and unlocks after an hour" do
      Devise.maximum_attempts.times { user.valid_for_authentication? { false } }

      expect(user.reload).to be_access_locked
      expect(user.active_for_authentication?).to be(false)

      travel_to(61.minutes.from_now) do
        expect(user.valid_for_authentication? { true }).to be(true)
        expect(user.reload).not_to be_access_locked
      end
    end
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
