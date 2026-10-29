require "rails_helper"

RSpec.describe AuditVersion do
  let!(:user) { create(:user) }
  let(:row) { AuditVersion.last }

  it "cannot be updated through the app" do
    expect { row.update!(whodunnit: "someone else") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { row.update_columns(whodunnit: "someone else") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(row.reload.whodunnit).not_to eq("someone else")
  end

  it "cannot be destroyed through the app" do
    expect { row.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { row.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(AuditVersion.count).to eq(1)
  end

  it "is not removed when the audited record is deleted (no foreign key)" do
    user.destroy!

    expect(AuditVersion.where(item_id: user.id).pluck(:event)).to contain_exactly("create", "destroy")
  end

  it "refuses an unknown event, and a missing actor never stays empty" do
    expect { AuditVersion.create!(item_type: "User", item_id: user.id, event: "wipe") }.to raise_error(ActiveRecord::StatementInvalid)
    expect(AuditVersion.create!(item_type: "User", item_id: user.id, event: "update").whodunnit).to start_with("system:")
  end
end
