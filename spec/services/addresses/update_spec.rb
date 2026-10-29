require "rails_helper"

RSpec.describe Addresses::Update do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:valid) { { address_line_1: "1 Market Street", address_line_2: "Suite 4", city: "San Francisco", state: "CA", postal_code: "94105", country: "US" } }

  def update(**changes) = described_class.call(user:, **valid.merge(changes))

  def messages(result) = result.errors.map(&:full_message)

  def saved = user.reload.attributes.slice(*User::ADDRESS_FIELDS.map(&:to_s))

  it "saves the address and returns the user" do
    result = update

    expect(result).to be_success
    expect(result.value).to eq(user)
    expect(user.reload).to have_attributes(valid)
  end

  it "normalizes what it saves" do
    update(address_line_1: "  1   Market Street ", city: " San  Francisco", state: " ca ", postal_code: " 94105-1234 ", country: "us")

    expect(user.reload).to have_attributes(address_line_1: "1 Market Street", city: "San Francisco", state: "CA", postal_code: "94105-1234", country: "US")
  end

  it "does not need line 2, and clears a saved one when it is left out" do
    update
    result = update(address_line_2: nil)

    expect(result).to be_success
    expect(user.reload.address_line_2).to be_nil
  end

  it "finishes the address step once the profile step is done" do
    stub_onboarding_steps(*real_onboarding_steps)
    user.update!(first_name: "Ada", last_name: "Lovelace", date_of_birth: Date.new(1990, 5, 21), phone: "+14155552671")
    Onboarding::Sync.call(user:)

    update

    expect(user.onboarding_steps.pluck(:step_key)).to contain_exactly("profile", "address")
  end

  describe "sending the same data again" do
    it "succeeds and writes nothing: updated_at stays" do
      update
      stamp = user.reload.updated_at

      result = travel_to(1.day.from_now) { update(state: "ca") }

      expect(result).to be_success
      expect(user.reload.updated_at).to eq(stamp)
    end
  end

  describe "a missing field" do
    it "is required, named by its field" do
      { address_line_1: "Address line 1", city: "City", state: "State", postal_code: "Postal code", country: "Country" }.each do |field, label|
        [ "", "   " ].each do |blank|
          result = update(field => blank)

          expect(result.code).to eq("VALIDATION_FAILED")
          expect(messages(result)).to eq([ "#{label} is required" ])
          expect(result.errors.first.attribute).to eq(field)
        end
      end
    end

    it "lists every missing field at once" do
      result = described_class.call(user:, address_line_1: "", city: "", state: "", postal_code: "", country: "")

      expect(messages(result)).to eq([ "Address line 1 is required", "City is required", "State is required", "Postal code is required", "Country is required" ])
    end
  end

  describe "a field that is filled but wrong" do
    it "is refused with a message that says what to do, and nothing is saved" do
      update
      before_state = saved

      bad = [
        [ { state: "ZZ" }, "State must be a two-letter US state code, for example CA" ],
        [ { state: "California" }, "State must be a two-letter US state code, for example CA" ],
        [ { postal_code: "1234" }, "Postal code must be a US ZIP code, for example 94105 or 94105-1234" ],
        [ { postal_code: "94105-12" }, "Postal code must be a US ZIP code, for example 94105 or 94105-1234" ],
        [ { postal_code: "ABCDE" }, "Postal code must be a US ZIP code, for example 94105 or 94105-1234" ],
        [ { country: "CA" }, "Country must be US. Only United States addresses are accepted" ],
        [ { city: "a" * 101 }, "City is too long (maximum is 100 characters)" ],
        [ { address_line_1: "a" * 101 }, "Address line 1 is too long (maximum is 100 characters)" ],
        [ { address_line_2: "a" * 101 }, "Address line 2 is too long (maximum is 100 characters)" ]
      ]
      bad.each do |changes, message|
        result = update(**changes)

        expect(result.code).to eq("VALIDATION_FAILED")
        expect(messages(result)).to eq([ message ])
      end
      expect(saved).to eq(before_state)
    end

    it "accepts every US state code and the two ZIP shapes" do
      ValidationRules::US_STATE_CODES.each { |code| expect(update(state: code)).to be_success }
      [ "00501", "94105", "94105-1234" ].each { |zip| expect(update(postal_code: zip)).to be_success }
    end

    it "never repeats the value that was sent" do
      result = update(postal_code: "secret-value-9")

      expect(messages(result).join).not_to include("secret-value-9")
    end
  end

  it "touches only the user it is given" do
    other = create(:user)
    update

    expect(other.reload).to have_attributes(address_line_1: nil, city: nil)
  end
end
