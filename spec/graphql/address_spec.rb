require "rails_helper"

RSpec.describe "Address", type: :request do
  let(:user) { create(:user) }
  let(:token) { token_for(user) }
  let(:fields) { "addressLine1 addressLine2 city state postalCode country" }
  let(:update_address) do
    "mutation($i: UpdateAddressInput!) { updateAddress(input: $i) { user { id #{fields} onboarding { completed currentStep steps { key completed } } } errors { message path code } } }"
  end
  let(:input) { { addressLine1: "1 Market Street", addressLine2: "Suite 4", city: "San Francisco", state: "CA", postalCode: "94105", country: "US" } }
  let(:profile_input) { { firstName: "Ada", lastName: "Lovelace", dateOfBirth: "1990-05-21", phone: "+14155552671" } }
  let(:update_profile) { "mutation($i: UpdateProfileInput!) { updateProfile(input: $i) { errors { code } } }" }

  def save_address(attributes = input, as: token) = gql(update_address, variables: { i: attributes }, token: as)

  def payload(body) = body.dig("data", "updateAddress")

  def error_code(body) = body.dig("errors", 0, "extensions", "code")

  it "saves the address, and me shows it" do
    body = save_address

    expect(payload(body)["errors"]).to eq([])
    expect(payload(body)["user"]).to include("id" => user.id, "addressLine1" => "1 Market Street", "addressLine2" => "Suite 4", "city" => "San Francisco", "state" => "CA", "postalCode" => "94105", "country" => "US")
    expect(gql("{ me { #{fields} } }", token:).dig("data", "me")).to include("city" => "San Francisco", "postalCode" => "94105")
  end

  it "shows empty fields in me until the address is saved" do
    expect(gql("{ me { #{fields} } }", token:).dig("data", "me").values).to all(be_nil)
  end

  it "does not need line 2" do
    body = save_address(input.except(:addressLine2))

    expect(payload(body)["errors"]).to eq([])
    expect(payload(body)["user"]["addressLine2"]).to be_nil
  end

  describe "failures" do
    it "says an empty field is required, with the field in the path" do
      body = save_address(input.merge(city: "", postalCode: "  "))

      expect(payload(body)["user"]).to be_nil
      expect(payload(body)["errors"]).to eq([
        { "message" => "City is required", "path" => [ "input", "city" ], "code" => "VALIDATION_FAILED" },
        { "message" => "Postal code is required", "path" => [ "input", "postalCode" ], "code" => "VALIDATION_FAILED" }
      ])
    end

    it "says what is wrong with a filled field, and only US is accepted" do
      body = save_address(input.merge(state: "ZZ", postalCode: "123", country: "CA"))

      expect(payload(body)["errors"].map { |e| [ e["path"].last, e["message"] ] }).to contain_exactly(
        [ "state", "State must be a two-letter US state code, for example CA" ],
        [ "postalCode", "Postal code must be a US ZIP code, for example 94105 or 94105-1234" ],
        [ "country", "Country must be US. Only United States addresses are accepted" ]
      )
      expect(user.reload.city).to be_nil
    end

    it "handles hostile text as plain text, never a 500" do
      [ "' OR 1=1 --", "<script>alert(1)</script>", "🔥" * 30, "x" * 5000 ].each do |value|
        body = save_address(input.merge(addressLine1: value, city: value))

        expect(body["errors"].to_a + payload(body).to_h.fetch("errors", [])).not_to be_empty if value.length > 100
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "who may call it" do
    it "is UNAUTHENTICATED without a login, with a garbage token, or with bad input as nobody" do
      expect(error_code(save_address(input, as: nil))).to eq("UNAUTHENTICATED")
      expect(error_code(save_address(input, as: "garbage"))).to eq("UNAUTHENTICATED")
      expect(error_code(gql(update_address, variables: { i: {} }))).to eq("UNAUTHENTICATED")
    end

    it "lets every role save its own address" do
      User.roles.each_key do |role|
        member = create(:user, role.to_sym)

        expect(payload(save_address(input, as: token_for(member)))["errors"]).to eq([])
        expect(member.reload.city).to eq("San Francisco")
      end
    end

    it "has no way to name another user: the input takes no id, and extra fields are rejected by the schema" do
      other = create(:user)

      [ { userId: other.id }, { id: other.id }, { email: "x@example.test" }, { role: "SUPER_ADMIN" } ].each do |extra|
        expect(save_address(input.merge(extra))["errors"]).to be_present
      end
      expect(other.reload.city).to be_nil
      expect(user.reload.city).to be_nil
    end

    it "keeps each user's address apart" do
      other = create(:user)
      save_address
      save_address(input.merge(city: "Oakland"), as: token_for(other))

      expect(gql("{ me { city } }", token:).dig("data", "me", "city")).to eq("San Francisco")
      expect(gql("{ me { city } }", token: token_for(other)).dig("data", "me", "city")).to eq("Oakland")
    end
  end

  describe "the address step of the real registry" do
    before { stub_onboarding_steps(*real_onboarding_steps) }

    it "lists profile, then address, and blocks a member until both are saved" do
      expect(gql("{ me { onboarding { completed currentStep steps { key } } } }", token:).dig("data", "me", "onboarding"))
        .to eq("completed" => false, "currentStep" => "profile", "steps" => [ { "key" => "profile" }, { "key" => "address" }, { "key" => "terms" } ])
    end

    it "lets updateAddress through the gate, and the server finishes the step when the profile is done too" do
      gql(update_profile, variables: { i: profile_input }, token:)
      expect(user.onboarding_steps.pluck(:step_key)).to eq(%w[profile])

      onboarding = payload(save_address).dig("user", "onboarding")

      expect(onboarding).to eq(
        "completed" => false, "currentStep" => "terms",
        "steps" => [ { "key" => "profile", "completed" => true }, { "key" => "address", "completed" => true }, { "key" => "terms", "completed" => false } ]
      )
    end

    it "saves the address first, and finishes both steps once the profile arrives" do
      expect(payload(save_address).dig("user", "onboarding", "currentStep")).to eq("profile")
      expect(user.onboarding_steps).to be_empty

      gql(update_profile, variables: { i: profile_input }, token:)

      expect(user.onboarding_steps.pluck(:step_key)).to contain_exactly("profile", "address")
    end

    it "keeps the step open when the address is refused" do
      gql(update_profile, variables: { i: profile_input }, token:)
      save_address(input.merge(postalCode: "123"))

      expect(user.onboarding_steps.pluck(:step_key)).to eq(%w[profile])
    end

    it "does not block a super_admin, who has no address step" do
      admin_token = token_for(create(:user, :super_admin))

      expect(gql("{ me { onboarding { completed steps { key } } } }", token: admin_token).dig("data", "me", "onboarding")).to eq("completed" => true, "steps" => [])
    end
  end
end
