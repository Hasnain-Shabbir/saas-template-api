require "rails_helper"

RSpec.describe EmailLog do
  it "has a valid factory" do
    expect(build(:email_log)).to be_valid
  end

  it "keeps rows for 6 years" do
    expect(described_class::RETENTION).to eq(6.years)
  end

  it "stores the recipient trimmed and in lower case" do
    expect(create(:email_log, recipient: "  Person@Example.TEST ").recipient).to eq("person@example.test")
  end

  it "refuses an unknown status, in the model and in the database" do
    expect(build(:email_log, status: "queued")).not_to be_valid
    expect { create(:email_log).update_columns(status: "queued") }.to raise_error(ActiveRecord::StatementInvalid, /email_logs_status_values/)
  end

  it "requires a recipient, a mailer and an action" do
    log = described_class.new(status: "sent")

    expect(log).not_to be_valid
    expect(log.errors.attribute_names).to include(:recipient, :mailer, :action)
  end

  it "refuses a body or a subject over the limit, in the model and in the database" do
    expect(build(:email_log, body: "a" * (ValidationRules::EMAIL_LOG_BODY_MAX_LENGTH + 1))).not_to be_valid
    expect(build(:email_log, subject: "a" * (ValidationRules::EMAIL_LOG_SUBJECT_MAX_LENGTH + 1))).not_to be_valid
    expect { create(:email_log).update_columns(body: "a" * (ValidationRules::EMAIL_LOG_BODY_MAX_LENGTH + 1)) }
      .to raise_error(ActiveRecord::StatementInvalid, /email_logs_body_length/)
  end

  describe ".expired" do
    it "returns only rows older than the retention period" do
      old = create(:email_log, created_at: described_class::RETENTION.ago - 1.day)
      create(:email_log, created_at: described_class::RETENTION.ago + 1.day)

      expect(described_class.expired).to contain_exactly(old)
    end
  end

  describe ".recipient_matching" do
    let!(:jo) { create(:email_log, recipient: "jo@example.test") }
    let!(:sam) { create(:email_log, recipient: "sam@other.test") }

    it "finds a row by half an address, in any letter case" do
      expect(described_class.recipient_matching("JO@exam")).to contain_exactly(jo)
      expect(described_class.recipient_matching("other")).to contain_exactly(sam)
    end

    it "matches % and _ literally, not as wildcards" do
      expect(described_class.recipient_matching("%")).to be_empty
      expect(described_class.recipient_matching("j_@")).to be_empty
    end
  end
end
