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

      %i[index? create? update? destroy?].each do |action|
        it "denies #{action} (nothing allows it yet)" do
          expect(described_class.new(user, user).public_send(action)).to be(false)
        end
      end
    end
  end

  it "denies everything when nobody is logged in" do
    policy = described_class.new(nil, other)

    expect(%i[index? show? create? update? destroy? logout? change_email? update_profile? update_address? accept_terms?].map { |action| policy.public_send(action) }).to all(be(false))
  end
end
