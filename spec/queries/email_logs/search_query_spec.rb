require "rails_helper"

RSpec.describe EmailLogs::SearchQuery do
  let!(:jan_sent) { create(:email_log, recipient: "jo@example.test", status: "sent", created_at: Time.zone.local(2026, 1, 10, 12)) }
  let!(:feb_failed) { create(:email_log, recipient: "sam@other.test", status: "failed", sent_at: nil, created_at: Time.zone.local(2026, 2, 5, 23, 30)) }
  let!(:mar_sent) { create(:email_log, recipient: "jo@other.test", status: "sent", created_at: Time.zone.local(2026, 3, 1, 8)) }

  it "returns everything, newest first, when no filter is given" do
    expect(described_class.call.to_a).to eq([ mar_sent, feb_failed, jan_sent ])
  end

  it "ignores blank filters" do
    expect(described_class.call(from: nil, to: "", status: "", search: " ").to_a).to eq([ mar_sent, feb_failed, jan_sent ])
  end

  it "filters by status" do
    expect(described_class.call(status: "failed")).to contain_exactly(feb_failed)
    expect(described_class.call(status: :sent)).to contain_exactly(jan_sent, mar_sent)
  end

  it "filters by a date range, both days included, and by the day only when a time is given" do
    expect(described_class.call(from: Date.new(2026, 2, 5), to: Date.new(2026, 2, 5))).to contain_exactly(feb_failed)
    expect(described_class.call(from: Date.new(2026, 2, 1))).to contain_exactly(feb_failed, mar_sent)
    expect(described_class.call(to: Date.new(2026, 1, 31))).to contain_exactly(jan_sent)
    expect(described_class.call(from: Time.zone.local(2026, 2, 5, 23), to: Time.zone.local(2026, 2, 5, 23))).to contain_exactly(feb_failed)
  end

  it "searches by half an address" do
    expect(described_class.call(search: "jo@")).to contain_exactly(jan_sent, mar_sent)
    expect(described_class.call(search: "OTHER.test")).to contain_exactly(feb_failed, mar_sent)
  end

  it "combines the filters" do
    expect(described_class.call(status: "sent", search: "other", from: Date.new(2026, 2, 1))).to contain_exactly(mar_sent)
  end

  it "returns nothing for an unknown status" do
    expect(described_class.call(status: "queued")).to be_empty
  end

  it "keeps to the scope it is given" do
    expect(described_class.call(scope: EmailLog.where(recipient: "jo@example.test"), search: "jo")).to contain_exactly(jan_sent)
  end
end
