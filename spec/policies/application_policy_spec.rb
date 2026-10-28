require "rails_helper"

RSpec.describe ApplicationPolicy do
  %i[index? show? create? update? destroy?].each do |action|
    User.roles.each_key do |role|
      it "denies #{action} to a #{role}" do
        expect(described_class.new(build(:user, role.to_sym), Object.new).public_send(action)).to be(false)
      end
    end

    it "denies #{action} when nobody is logged in" do
      expect(described_class.new(nil, Object.new).public_send(action)).to be(false)
    end
  end
end
