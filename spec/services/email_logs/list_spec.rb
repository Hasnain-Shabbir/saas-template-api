require "rails_helper"

RSpec.describe EmailLogs::List do
  before { create_list(:email_log, 7) }

  it "returns the first page with the default size, newest first" do
    page = described_class.call.value

    expect(page).to have_attributes(page: 1, per_page: ValidationRules::PAGE_SIZE_DEFAULT, total_count: 7, total_pages: 1)
    expect(page.items.map(&:created_at)).to eq(page.items.map(&:created_at).sort.reverse)
  end

  it "splits the rows into pages that do not overlap" do
    first = described_class.call(per_page: 3, page: 1).value
    second = described_class.call(per_page: 3, page: 2).value
    third = described_class.call(per_page: 3, page: 3).value
    fourth = described_class.call(per_page: 3, page: 4).value

    expect(first).to have_attributes(total_count: 7, total_pages: 3)
    expect((first.items + second.items + third.items).map(&:id).uniq.size).to eq(7)
    expect(third.items.size).to eq(1)
    expect(fourth.items).to be_empty
  end

  it "brings a page below 1 and a size out of range into range" do
    expect(described_class.call(page: -5).value.page).to eq(1)
    expect(described_class.call(page: 0).value.page).to eq(1)
    expect(described_class.call(per_page: 0).value.per_page).to eq(1)
    expect(described_class.call(per_page: -3).value.per_page).to eq(1)
    expect(described_class.call(per_page: 1_000_000).value.per_page).to eq(ValidationRules::PAGE_SIZE_MAX)
  end

  it "counts only the rows that match the filters" do
    create(:email_log, recipient: "findme@example.test", status: "failed", sent_at: nil)

    page = described_class.call(status: "failed", search: " FINDME ").value

    expect(page.total_count).to eq(1)
    expect(page.items.map(&:recipient)).to eq([ "findme@example.test" ])
  end

  it "has no pages when nothing matches" do
    page = described_class.call(search: "nobody").value

    expect(page).to have_attributes(items: [], total_count: 0, total_pages: 0)
  end

  it "cuts a search over the address limit instead of failing" do
    expect(described_class.call(search: "a" * 5_000)).to be_success
  end
end
