require "rails_helper"

RSpec.describe User, "profile" do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  def raw(column) = described_class.connection.select_value("SELECT #{column} FROM users WHERE id = '#{user.id}'")

  it "starts with no profile, and the model still accepts that" do
    expect(user).to have_attributes(first_name: nil, last_name: nil, date_of_birth: nil, phone: nil)
    expect(user).to be_valid
    expect(user.profile_complete?).to be(false)
  end

  describe "profile_complete?" do
    it "is true only when all four fields are filled" do
      user.assign_attributes(first_name: "Ada", last_name: "Lovelace", date_of_birth: Date.new(1990, 5, 21))
      expect(user.profile_complete?).to be(false)

      user.phone = "+14155552671"
      expect(user.profile_complete?).to be(true)
    end
  end

  describe "normalizing" do
    it "trims and squeezes spaces in names, and turns a blank name into nothing" do
      user.update!(first_name: "  Mary   Ann ", last_name: "   ")

      expect(user.first_name).to eq("Mary Ann")
      expect(user.last_name).to be_nil
    end

    it "removes spaces and dashes from a phone number" do
      user.update!(phone: " +1 415-555 2671 ")

      expect(user.phone).to eq("+14155552671")
    end
  end

  describe "names" do
    it "may be 100 characters, not 101" do
      expect(build(:user, first_name: "a" * 100, last_name: "b" * 100)).to be_valid
      expect(build(:user, first_name: "a" * 101)).not_to be_valid
      expect(build(:user, last_name: "b" * 101)).not_to be_valid
    end

    it "keeps the database limit too" do
      user # create it before the savepoints, so a rollback does not undo the insert
      # Raw SQL for the empty name: `normalizes` would turn "" into nil before it reaches the database.
      # A failed statement aborts the surrounding test transaction, so each one runs in its own savepoint.
      expect { User.transaction(requires_new: true) { user.update_column(:first_name, "a" * 101) } }
        .to raise_error(ActiveRecord::StatementInvalid, /users_first_name_length/)
      expect { User.transaction(requires_new: true) { described_class.where(id: user.id).update_all("last_name = ''") } }
        .to raise_error(ActiveRecord::StatementInvalid, /users_last_name_length/)
    end
  end

  describe "phone" do
    it "accepts the international format" do
      [ "+14155552671", "+442071838750", "+9715012345" ].each { |phone| expect(build(:user, phone:)).to be_valid, phone }
    end

    it "refuses anything else, with a message that shows the format" do
      [ "14155552671", "+0123456789", "+1234567", "+1234567890123456", "+1415555267a", "0014155552671", "+1 (415) 555", "' OR 1=1 --" ].each do |phone|
        candidate = build(:user, phone:)

        expect(candidate).not_to be_valid, phone
        expect(candidate.errors[:phone]).to eq([ Errors::PHONE_INVALID.message ])
      end
    end
  end

  describe "date of birth" do
    around { |example| travel_to(Time.zone.local(2026, 10, 29, 12)) { example.run } }

    it "accepts today and 120 years ago" do
      expect(build(:user, date_of_birth: Date.new(2026, 10, 29))).to be_valid
      expect(build(:user, date_of_birth: Date.new(1906, 10, 29))).to be_valid
    end

    it "refuses tomorrow, and one day more than 120 years ago" do
      future = build(:user, date_of_birth: Date.new(2026, 10, 30))
      old = build(:user, date_of_birth: Date.new(1906, 10, 28))

      expect(future).not_to be_valid
      expect(future.errors[:date_of_birth]).to eq([ Errors::DATE_OF_BIRTH_IN_FUTURE.message ])
      expect(old).not_to be_valid
      expect(old.errors[:date_of_birth]).to eq([ Errors::DATE_OF_BIRTH_TOO_OLD.message ])
    end

    it "is a Date for the model" do
      user.update!(date_of_birth: "1990-05-21")

      expect(user.reload.date_of_birth).to eq(Date.new(1990, 5, 21))
    end
  end

  describe "storage" do
    before { user.update!(first_name: "Ada", last_name: "Lovelace", date_of_birth: Date.new(1990, 5, 21), phone: "+14155552671") }

    it "stores date of birth and phone as ciphertext, never the plain value" do
      expect(raw("phone")).not_to include("4155552671")
      expect(raw("date_of_birth")).not_to include("1990")
      expect(user.reload).to have_attributes(date_of_birth: Date.new(1990, 5, 21), phone: "+14155552671")
    end

    it "stores names in plain text, on purpose (the frontend will search by name)" do
      expect(raw("first_name")).to eq("Ada")
      expect(raw("last_name")).to eq("Lovelace")
    end

    it "does not see a change when the same data is assigned again (the encrypted fields compare by their plain value)" do
      user.reload
      user.assign_attributes(first_name: "Ada", date_of_birth: "1990-05-21", phone: "+1 415 555 2671")

      expect(user.changed?).to be(false)
    end
  end
end
