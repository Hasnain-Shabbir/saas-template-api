require "rails_helper"

RSpec.describe Audit::RecordRead do
  let(:viewed) { create(:user, :with_profile, :with_address) }
  let(:admin) { create(:user, :super_admin) }

  it "writes one row with ids and the group name" do
    result = described_class.call(reader: admin.id, record: viewed, group: :contact, request_id: "req-1")

    expect(result).to be_success
    expect(ReadAudit.sole).to have_attributes(reader: admin.id, item_type: "User", item_id: viewed.id, field_group: "contact", request_id: "req-1")
  end

  it "does not log a person reading their own data" do
    expect { described_class.call(reader: viewed.id, record: viewed, group: "address") }.not_to change(ReadAudit, :count)
  end

  it "stores no value of the record" do
    described_class.call(reader: admin.id, record: viewed, group: "address")

    stored = ReadAudit.sole.attributes.to_json
    expect(stored).not_to include("Ada", "Lovelace", "+14155552671", "1990-05-21", "1 Market Street", "San Francisco", "94105", viewed.email)
  end

  it "raises when the row cannot be written, so the caller returns no data" do
    expect { described_class.call(reader: admin.id, record: viewed, group: "everything") }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
