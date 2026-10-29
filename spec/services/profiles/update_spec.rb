require "rails_helper"

RSpec.describe Profiles::Update do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:valid) { { first_name: "Ada", last_name: "Lovelace", date_of_birth: Date.new(1990, 5, 21), phone: "+14155552671" } }

  def update(**changes) = described_class.call(user:, **valid.merge(changes))

  def messages(result) = result.errors.map(&:full_message)

  it "saves all four fields and returns the user" do
    result = update

    expect(result).to be_success
    expect(result.value).to eq(user)
    expect(user.reload).to have_attributes(valid)
  end

  it "normalizes what it saves" do
    update(first_name: "  Ada ", phone: "+1 415-555-2671")

    expect(user.reload).to have_attributes(first_name: "Ada", phone: "+14155552671")
  end

  describe "sending the same data again" do
    it "succeeds and writes nothing: updated_at stays" do
      update
      stamp = user.reload.updated_at

      result = travel_to(1.day.from_now) { update(phone: "+1 415 555 2671") }

      expect(result).to be_success
      expect(user.reload.updated_at).to eq(stamp)
    end

    it "updates only when something changed" do
      update
      result = travel_to(1.day.from_now) { update(last_name: "King") }

      expect(result).to be_success
      expect(user.reload).to have_attributes(first_name: "Ada", last_name: "King")
      expect(user.updated_at).to be > 12.hours.ago
    end
  end

  describe "a missing field" do
    it "is required, named by its field" do
      { first_name: "First name", last_name: "Last name", phone: "Phone" }.each do |field, label|
        [ "", "   " ].each do |blank|
          result = update(field => blank)

          expect(result.code).to eq("VALIDATION_FAILED")
          expect(messages(result)).to eq([ "#{label} is required" ])
          expect(result.errors.first.attribute).to eq(field)
        end
      end
    end

    it "is required for the date of birth too" do
      result = update(date_of_birth: nil)

      expect(messages(result)).to eq([ "Date of birth is required" ])
    end

    it "lists every missing field at once" do
      result = described_class.call(user:, first_name: "", last_name: "", date_of_birth: nil, phone: "")

      expect(messages(result)).to eq([ "First name is required", "Last name is required", "Date of birth is required", "Phone is required" ])
    end
  end

  describe "a field that is filled but wrong" do
    it "is refused with a message that says what to do, and nothing is saved" do
      update
      before_state = user.reload.attributes.slice(*User::PROFILE_FIELDS.map(&:to_s))

      bad = [
        [ { phone: "4155552671" }, "Phone must be in international format, for example +14155552671" ],
        [ { date_of_birth: Date.current + 1 }, "Date of birth cannot be in the future" ],
        [ { date_of_birth: Date.new(1800, 1, 1) }, "Date of birth is too far in the past. Check the year" ],
        [ { first_name: "a" * 101 }, "First name is too long (maximum is 100 characters)" ]
      ]
      bad.each do |changes, message|
        result = update(**changes)

        expect(result.code).to eq("VALIDATION_FAILED")
        expect(messages(result)).to eq([ message ])
      end
      expect(user.reload.attributes.slice(*User::PROFILE_FIELDS.map(&:to_s))).to eq(before_state)
    end

    it "never repeats the value that was sent" do
      result = update(phone: "secret-value-9")

      expect(messages(result).join).not_to include("secret-value-9")
    end
  end

  it "touches only the user it is given" do
    other = create(:user)
    update

    expect(other.reload).to have_attributes(first_name: nil, phone: nil)
  end
end
