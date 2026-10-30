require "rails_helper"

RSpec.describe Users::SearchQuery do
  let!(:ada) { create(:user, :member, email: "ada@example.test", first_name: "Ada", last_name: "Lovelace", created_at: Time.zone.local(2026, 1, 10, 12)) }
  let!(:sam) { create(:user, :super_admin, email: "sam@other.test", first_name: "Sam", last_name: "Smith", created_at: Time.zone.local(2026, 2, 5, 23, 30)) }
  let!(:bob) { create(:user, :member, email: "bob@other.test", created_at: Time.zone.local(2026, 3, 1, 8)) }

  it "returns everything, newest first, when no filter is given" do
    expect(described_class.call.to_a).to eq([ bob, sam, ada ])
  end

  it "ignores blank filters" do
    expect(described_class.call(role: "", created_from: nil, created_to: "", search: " ").to_a).to eq([ bob, sam, ada ])
  end

  it "filters by role" do
    expect(described_class.call(role: "super_admin")).to contain_exactly(sam)
    expect(described_class.call(role: :member)).to contain_exactly(ada, bob)
    expect(described_class.call(role: "owner")).to be_empty
  end

  it "filters by a date range, both days included" do
    expect(described_class.call(created_from: Date.new(2026, 2, 5), created_to: Date.new(2026, 2, 5))).to contain_exactly(sam)
    expect(described_class.call(created_from: Date.new(2026, 2, 1))).to contain_exactly(sam, bob)
    expect(described_class.call(created_to: Date.new(2026, 1, 31))).to contain_exactly(ada)
  end

  it "searches part of the email, first name or last name, in any letter case" do
    expect(described_class.call(search: "OTHER.test")).to contain_exactly(sam, bob)
    expect(described_class.call(search: "ada")).to contain_exactly(ada)
    expect(described_class.call(search: "lACE")).to contain_exactly(ada)
    expect(described_class.call(search: "smi")).to contain_exactly(sam)
  end

  it "matches % and _ literally" do
    expect(described_class.call(search: "%")).to be_empty
    expect(described_class.call(search: "a_a")).to be_empty
  end

  it "does not run SQL typed into the search" do
    expect(described_class.call(search: "'; DROP TABLE users; --")).to be_empty
    expect(User.count).to eq(3)
  end

  it "combines the filters" do
    expect(described_class.call(role: "member", search: "other", created_from: Date.new(2026, 2, 1))).to contain_exactly(bob)
  end

  it "keeps to the scope it is given" do
    expect(described_class.call(scope: User.where(id: ada.id), search: "o")).to contain_exactly(ada)
  end
end
