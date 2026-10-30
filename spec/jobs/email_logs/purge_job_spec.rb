require "rails_helper"

RSpec.describe EmailLogs::PurgeJob, type: :job do
  it "runs on the default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end

  it "deletes expired rows" do
    create(:email_log, created_at: EmailLog::RETENTION.ago - 1.day)
    keep = create(:email_log)

    described_class.perform_now

    expect(EmailLog.all).to contain_exactly(keep)
  end

  it "is scheduled every day in config/schedule.yml" do
    entry = YAML.safe_load_file(Rails.root.join("config/schedule.yml")).values.find { |job| job["class"] == described_class.name }

    expect(entry).to include("cron" => a_string_matching(/\A\d+ \d+ \* \* \*\z/))
  end
end
