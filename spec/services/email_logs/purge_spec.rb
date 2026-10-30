require "rails_helper"

RSpec.describe EmailLogs::Purge do
  let!(:old) { create(:email_log, created_at: EmailLog::RETENTION.ago - 1.day) }
  let!(:recent) { create(:email_log, created_at: EmailLog::RETENTION.ago + 1.day) }

  it "deletes the rows older than the retention period and keeps the rest" do
    result = described_class.call

    expect(result).to be_success
    expect(result.value).to eq(1)
    expect(EmailLog.all).to contain_exactly(recent)
  end

  it "is safe to run twice" do
    described_class.call

    expect(described_class.call.value).to eq(0)
    expect(EmailLog.count).to eq(1)
  end

  it "works through more than one batch" do
    stub_const("#{described_class}::BATCH_SIZE", 2)
    create_list(:email_log, 4, created_at: EmailLog::RETENTION.ago - 1.day)

    expect(described_class.call.value).to eq(5)
    expect(EmailLog.all).to contain_exactly(recent)
  end
end
