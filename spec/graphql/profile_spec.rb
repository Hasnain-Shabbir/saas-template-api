require "rails_helper"

RSpec.describe "Profile", type: :request do
  let(:user) { create(:user) }
  let(:token) { token_for(user) }
  let(:update_profile) do
    "mutation($i: UpdateProfileInput!) { updateProfile(input: $i) { user { id firstName lastName dateOfBirth phone } errors { message path code } } }"
  end
  let(:me) { "{ me { id firstName lastName dateOfBirth phone } }" }
  let(:input) { { firstName: "Ada", lastName: "Lovelace", dateOfBirth: "1990-05-21", phone: "+14155552671" } }

  def save_profile(attributes = input, as: token) = gql(update_profile, variables: { i: attributes }, token: as)

  def payload(body) = body.dig("data", "updateProfile")

  def error_code(body) = body.dig("errors", 0, "extensions", "code")

  it "saves the profile, and me shows it" do
    body = save_profile

    expect(payload(body)).to eq("user" => { "id" => user.id, "firstName" => "Ada", "lastName" => "Lovelace", "dateOfBirth" => "1990-05-21", "phone" => "+14155552671" }, "errors" => [])
    expect(gql(me, token:).dig("data", "me")).to include("firstName" => "Ada", "dateOfBirth" => "1990-05-21", "phone" => "+14155552671")
  end

  it "shows empty fields in me until the profile is saved" do
    expect(gql(me, token:).dig("data", "me")).to include("firstName" => nil, "lastName" => nil, "dateOfBirth" => nil, "phone" => nil)
  end

  it "does nothing when the same data is sent again" do
    save_profile
    stamp = user.reload.updated_at

    expect(payload(save_profile(input.merge(phone: "+1 415 555 2671")))["errors"]).to eq([])
    expect(user.reload.updated_at).to eq(stamp)
  end

  it "updates the profile when the data changed" do
    save_profile
    save_profile(input.merge(lastName: "King"))

    expect(user.reload.last_name).to eq("King")
  end

  describe "failures" do
    it "says an empty field is required, with the field in the path" do
      body = save_profile(input.merge(firstName: "", phone: "  "))

      expect(payload(body)["user"]).to be_nil
      expect(payload(body)["errors"]).to eq([
        { "message" => "First name is required", "path" => [ "input", "firstName" ], "code" => "VALIDATION_FAILED" },
        { "message" => "Phone is required", "path" => [ "input", "phone" ], "code" => "VALIDATION_FAILED" }
      ])
    end

    it "says what is wrong with a filled field" do
      body = save_profile(input.merge(phone: "123", dateOfBirth: (Date.current + 1).iso8601))

      expect(payload(body)["errors"].map { |e| [ e["path"].last, e["message"] ] }).to contain_exactly(
        [ "dateOfBirth", "Date of birth cannot be in the future" ],
        [ "phone", "Phone must be in international format, for example +14155552671" ]
      )
      expect(user.reload.phone).to be_nil
    end

    it "refuses a date that is not a date, without a 500" do
      body = save_profile(input.merge(dateOfBirth: "not-a-date"))

      expect(body["errors"]).to be_present
      expect(response).to have_http_status(:ok)
      expect(user.reload.date_of_birth).to be_nil
    end

    it "handles hostile text as plain text, never a 500" do
      [ "' OR 1=1 --", "<script>alert(1)</script>", "🔥" * 30, "x" * 5000 ].each do |value|
        body = save_profile(input.merge(firstName: value, lastName: value))

        expect(body["errors"].to_a + payload(body).to_h.fetch("errors", [])).not_to be_empty if value.length > 100
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "who may call it" do
    it "is UNAUTHENTICATED without a login, with a garbage token, or with bad input as nobody" do
      expect(error_code(save_profile(input, as: nil))).to eq("UNAUTHENTICATED")
      expect(error_code(save_profile(input, as: "garbage"))).to eq("UNAUTHENTICATED")
      expect(error_code(gql(update_profile, variables: { i: {} }))).to eq("UNAUTHENTICATED")
    end

    it "lets every role save its own profile" do
      User.roles.each_key do |role|
        member = create(:user, role.to_sym)

        expect(payload(save_profile(input, as: token_for(member)))["errors"]).to eq([])
        expect(member.reload.first_name).to eq("Ada")
      end
    end

    it "has no way to name another user: the input takes no id, and extra fields are rejected by the schema" do
      other = create(:user)

      [ { userId: other.id }, { id: other.id }, { email: "x@example.test" }, { role: "SUPER_ADMIN" } ].each do |extra|
        expect(save_profile(input.merge(extra))["errors"]).to be_present
      end
      expect(other.reload.first_name).to be_nil
      expect(user.reload.first_name).to be_nil
    end

    it "keeps each user's profile apart" do
      other = create(:user)
      save_profile
      save_profile(input.merge(firstName: "Grace"), as: token_for(other))

      expect(gql(me, token:).dig("data", "me", "firstName")).to eq("Ada")
      expect(gql(me, token: token_for(other)).dig("data", "me", "firstName")).to eq("Grace")
    end
  end

  describe "the profile step of the real registry" do
    let(:other_operation) { "mutation { requestEmailChange(input: { newEmail: \"fresh@example.test\", password: \"correct horse battery\" }) { success errors { code } } }" }
    let(:save_with_progress) do
      "mutation($i: UpdateProfileInput!) { updateProfile(input: $i) { user { onboarding { completed currentStep steps { key completed } } } errors { code } } }"
    end

    before { stub_onboarding_steps(*real_onboarding_steps) }

    it "blocks a member until the profile is saved" do
      expect(error_code(gql(other_operation, token:))).to eq("ONBOARDING_REQUIRED")
      expect(gql("{ me { onboarding { completed currentStep } } }", token:).dig("data", "me", "onboarding")).to eq("completed" => false, "currentStep" => "profile")
    end

    it "lets updateProfile through the gate, and the server finishes the profile step: the response and me show it" do
      body = gql(save_with_progress, variables: { i: input }, token:)

      expect(body.dig("data", "updateProfile", "user", "onboarding")).to eq(
        "completed" => false, "currentStep" => "address",
        "steps" => [ { "key" => "profile", "completed" => true }, { "key" => "address", "completed" => false }, { "key" => "terms", "completed" => false } ]
      )
      expect(gql("{ me { onboarding { currentStep } } }", token:).dig("data", "me", "onboarding", "currentStep")).to eq("address")
      expect(error_code(gql(other_operation, token:))).to eq("ONBOARDING_REQUIRED")
    end

    it "opens the rest of the API when the address and terms steps are done too" do
      save_profile
      user.reload.update!(address_line_1: "1 Market Street", city: "San Francisco", state: "CA", postal_code: "94105", country: "US",
                          terms_version: Terms::Current::VERSION, terms_accepted_at: Time.current)
      Onboarding::Sync.call(user:)

      expect(gql(other_operation, token:).dig("data", "requestEmailChange", "success")).to be(true)
    end

    it "keeps the step open when the profile is refused" do
      body = gql(save_with_progress, variables: { i: input.merge(phone: "123") }, token:)

      expect(body.dig("data", "updateProfile", "errors", 0, "code")).to eq("VALIDATION_FAILED")
      expect(user.onboarding_steps).to be_empty
    end

    it "keeps the first completed_at when the profile is saved again" do
      save_profile
      stamp = user.onboarding_steps.first.completed_at
      save_profile(input.merge(lastName: "King"))

      expect(user.onboarding_steps.count).to eq(1)
      expect(user.onboarding_steps.first.completed_at).to eq(stamp)
    end

    it "does not finish the step for another user" do
      save_profile(input, as: token_for(create(:user)))

      expect(user.onboarding_steps).to be_empty
    end

    it "does not block a super_admin, who has no profile step" do
      admin_token = token_for(create(:user, :super_admin))

      expect(gql("{ me { onboarding { completed steps { key } } } }", token: admin_token).dig("data", "me", "onboarding")).to eq("completed" => true, "steps" => [])
      expect(gql(other_operation, token: admin_token).dig("data", "requestEmailChange", "success")).to be(true)
    end
  end
end
