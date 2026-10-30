require "rails_helper"

RSpec.describe ReadAuditPolicy do
  it "lets only a super_admin read the log" do
    expect(described_class.new(create(:user, :super_admin), ReadAudit).index?).to be(true)
    expect(described_class.new(create(:user, :member), ReadAudit).index?).to be(false)
  end

  it "denies everything when nobody is logged in" do
    expect(described_class.new(nil, ReadAudit).index?).to be(false)
  end

  %i[show? create? update? destroy?].each do |action|
    it "denies #{action} to a super_admin (nothing allows it)" do
      expect(described_class.new(create(:user, :super_admin), ReadAudit).public_send(action)).to be(false)
    end
  end
end
