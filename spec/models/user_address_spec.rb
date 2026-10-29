require "rails_helper"

RSpec.describe User, "address" do
  let(:user) { create(:user) }

  it "starts with no address, and the model still accepts that" do
    expect(user).to have_attributes(address_line_1: nil, city: nil, state: nil, postal_code: nil, country: nil)
    expect(user).to be_valid
    expect(user.address_complete?).to be(false)
  end

  describe "address_complete?" do
    it "needs every field but line 2" do
      expect(build(:user, :with_address).address_complete?).to be(true)
      expect(build(:user, :with_address, address_line_2: "Suite 4").address_complete?).to be(true)
      expect(build(:user, :with_address, city: nil).address_complete?).to be(false)
      expect(build(:user, :with_address, postal_code: nil).address_complete?).to be(false)
    end
  end

  it "turns a blank value into nothing" do
    user.update!(address_line_1: "   ", address_line_2: "", city: " ", state: " ", postal_code: " ", country: " ")

    expect(user.reload).to have_attributes(address_line_1: nil, address_line_2: nil, city: nil, state: nil, postal_code: nil, country: nil)
  end

  it "keeps the database limits too" do
    user # create it before the savepoints, so a rollback does not undo the insert
    { address_line_1: "a" * 101, address_line_2: "a" * 101, city: "a" * 101, state: "CAL", postal_code: "1" * 11, country: "USA" }.each do |column, value|
      expect { User.transaction(requires_new: true) { user.update_column(column, value) } }
        .to raise_error(ActiveRecord::StatementInvalid, /users_#{column}_length/)
    end
  end
end
