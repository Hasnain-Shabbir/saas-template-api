require "rails_helper"

RSpec.describe UserPolicy do
  let(:other) { create(:user) }

  User.roles.each_key do |role|
    describe "as a #{role}" do
      let(:user) { create(:user, role.to_sym) }

      %i[show? logout? change_email? update_profile? update_address? accept_terms?].each do |action|
        it "allows #{action} on themselves" do
          expect(described_class.new(user, user).public_send(action)).to be(true)
        end

        it "denies #{action} on another user" do
          expect(described_class.new(user, other).public_send(action)).to be(false)
        end
      end

      it "allows index? (the admin list) only for a super_admin" do
        expect(described_class.new(user, User).index?).to be(role == "super_admin")
      end

      %i[archive? unarchive?].each do |action|
        it "allows #{action} only for a super_admin acting on a member" do
          expect(described_class.new(user, other).public_send(action)).to be(role == "super_admin")
        end

        it "denies #{action} on themselves and on a super_admin" do
          expect(described_class.new(user, user).public_send(action)).to be(false) if role == "super_admin"
          expect(described_class.new(user, create(:user, :super_admin)).public_send(action)).to be(false)
        end
      end

      %i[create? update? destroy?].each do |action|
        it "denies #{action} (nothing allows it yet)" do
          expect(described_class.new(user, user).public_send(action)).to be(false)
        end
      end
    end
  end

  it "denies everything when nobody is logged in" do
    policy = described_class.new(nil, other)

    expect(%i[index? archive? unarchive? show? create? update? destroy? logout? change_email? update_profile? update_address? accept_terms?].map { |action| policy.public_send(action) }).to all(be(false))
  end
end
