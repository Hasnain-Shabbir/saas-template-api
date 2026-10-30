require "rails_helper"

RSpec.describe ReadAudit do
  let(:subject_user) { create(:user) }
  let!(:row) do
    described_class.create!(reader: "reader-id", item_type: "User", item_id: subject_user.id, field_group: "contact", request_id: "req-1")
  end

  it "cannot be updated through the app" do
    expect { row.update!(reader: "someone else") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { row.update_columns(reader: "someone else") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(row.reload.reader).to eq("reader-id")
  end

  it "cannot be destroyed through the app" do
    expect { row.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { row.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(described_class.count).to eq(1)
  end

  it "is not removed when the viewed record is deleted (no foreign key)" do
    subject_user.destroy!

    expect(described_class.where(item_id: subject_user.id).count).to eq(1)
  end

  it "refuses an unknown field group, in the model and in the database" do
    unknown = described_class.new(reader: "r", item_type: "User", item_id: subject_user.id, field_group: "everything")

    expect(unknown).not_to be_valid
    expect { unknown.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "accepts every group in FIELD_GROUPS, in the model and in the database (a new group needs a migration)" do
    described_class::FIELD_GROUPS.each do |group|
      expect { described_class.create!(reader: "r", item_type: "User", item_id: subject_user.id, field_group: group) }.not_to raise_error
    end
    expect(described_class::FIELD_GROUPS).to include("email_body")
  end

  it "needs a reader, a record, and a group" do
    expect(described_class.new).not_to be_valid
    expect { described_class.new(item_type: "User", item_id: subject_user.id, field_group: "contact").save!(validate: false) }
      .to raise_error(ActiveRecord::NotNullViolation)
  end

  it "keeps rows for six years" do
    expect(described_class::RETENTION).to eq(6.years)
  end
end
