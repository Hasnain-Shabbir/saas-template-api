require "rails_helper"

RSpec.describe EmailLogPolicy do
  %i[index? show?].each do |action|
    it "lets only a super_admin use #{action}" do
      expect(described_class.new(create(:user, :super_admin), EmailLog).public_send(action)).to be(true)
      expect(described_class.new(create(:user, :member), EmailLog).public_send(action)).to be(false)
    end

    it "denies #{action} when nobody is logged in" do
      expect(described_class.new(nil, EmailLog).public_send(action)).to be(false)
    end
  end

  %i[create? update? destroy?].each do |action|
    it "denies #{action} to a super_admin (nothing allows it)" do
      expect(described_class.new(create(:user, :super_admin), EmailLog).public_send(action)).to be(false)
    end
  end
end
