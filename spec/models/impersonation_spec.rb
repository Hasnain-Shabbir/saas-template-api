require "rails_helper"

RSpec.describe Impersonation do
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { create(:user, :super_admin) }
  let(:member) { create(:user) }
  let!(:row) { create(:impersonation, impersonator: admin, target: member) }

  it "is valid with the factory defaults" do
    expect(row).to be_valid
  end

  describe "validations (and the matching database constraints)" do
    it "needs a category, in the model and in the database" do
      none = build(:impersonation, reason_category: nil)

      expect(none).not_to be_valid
      expect { none.save!(validate: false) }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "refuses an unknown category, in the model and in the database" do
      unknown = build(:impersonation, reason_category: "fun")

      expect(unknown).not_to be_valid
      expect { unknown.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "needs a note for the category other, in the model and in the database" do
      [ nil, " " ].each do |note|
        bare = build(:impersonation, reason_category: "other", reason: note)

        expect(bare).not_to be_valid
        expect(bare.errors[:reason]).to be_present
      end
      expect { build(:impersonation, reason_category: "other", reason: nil).save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid)
    end

    it "accepts the category other with a note" do
      expect(build(:impersonation, reason_category: "other", reason: "Checking a billing complaint")).to be_valid
    end

    it "does not need a note for the other categories, and a blank note is stored as empty" do
      described_class.reason_categories.each_key.reject { |category| category == "other" }.each do |category|
        expect(build(:impersonation, reason_category: category, reason: nil)).to be_valid
      end
      expect(build(:impersonation, reason: "  ").reason).to be_nil
    end

    it "refuses a note longer than the limit, in the model and in the database" do
      long = build(:impersonation, reason: "a" * (ValidationRules::IMPERSONATION_REASON_MAX_LENGTH + 1))

      expect(long).not_to be_valid
      expect { long.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "refuses to impersonate yourself, in the model and in the database" do
      own = build(:impersonation, impersonator: admin, target: admin)

      expect(own).not_to be_valid
      expect { own.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "refuses an expiry that is not after the start, in the database" do
      now = Time.current

      expect { build(:impersonation, started_at: now, expires_at: now).save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid)
    end

    it "refuses a token id used twice" do
      expect { create(:impersonation, jti: row.jti) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "refuses an unknown ending reason, in the model and in the database" do
      row.ended_at = Time.current
      row.ended_reason = "because"

      expect(row).not_to be_valid
      expect { row.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "needs the end time and the end reason together, in the database" do
      expect { row.update_columns(ended_at: Time.current) }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe "one open session per admin" do
    it "refuses a second open session for the same admin" do
      expect { create(:impersonation, impersonator: admin) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows a new session once the first one has ended" do
      row.update!(ended_at: Time.current, ended_reason: "stopped")

      expect { create(:impersonation, impersonator: admin) }.not_to raise_error
    end

    it "allows an open session for another admin" do
      expect { create(:impersonation) }.not_to raise_error
    end
  end

  describe "time" do
    it "lasts 30 minutes and is kept six years" do
      expect(described_class::TTL).to eq(30.minutes)
      expect(described_class::RETENTION).to eq(6.years)
      expect(row.expires_at - row.started_at).to be_within(1.second).of(30.minutes)
    end

    it "is active until it ends or runs out" do
      expect(row).to be_active
      travel_to(row.expires_at + 1.second) { expect(row).not_to be_active }
    end

    it "is not active after it was ended" do
      row.update!(ended_at: Time.current, ended_reason: "stopped")

      expect(row).not_to be_active
    end

    it "reports when it really ended" do
      expect(row.effective_end).to eq(row.expires_at)

      ended = Time.current.change(usec: 0)
      row.update!(ended_at: ended, ended_reason: "stopped")

      expect(row.effective_end).to eq(ended)
    end
  end

  describe "append only" do
    it "can be ended once, with a reason" do
      row.update!(ended_at: Time.current, ended_reason: "ended_by_system")

      expect(row.reload).to be_ended_as_ended_by_system
      expect(described_class.unended).to be_empty
    end

    it "cannot be edited after it ended" do
      row.update!(ended_at: Time.current, ended_reason: "stopped")

      expect { row.update!(ended_reason: "expired") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { row.update_columns(ended_reason: "expired") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(row.reload.ended_reason).to eq("stopped")
    end

    it "cannot change who, whom, why or when" do
      other = create(:user)

      expect { row.update!(target: other) }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { row.update!(reason: "something else") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { row.update!(expires_at: row.expires_at + 1.day) }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(row.reload.target_id).to eq(member.id)
    end

    it "cannot be destroyed through the app" do
      expect { row.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { row.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { row.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(described_class.count).to eq(1)
    end

    it "keeps either user from being deleted while the row exists" do
      expect { member.destroy! }.to raise_error(ActiveRecord::InvalidForeignKey)
      expect { admin.destroy! }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end
end
