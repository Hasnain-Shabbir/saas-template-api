require "rails_helper"

RSpec.describe "Terms", type: :request do
  let(:user) { create(:user) }
  let(:token) { token_for(user) }
  let(:accept_terms) do
    "mutation($i: AcceptTermsInput!) { acceptTerms(input: $i) { user { id termsVersion termsAcceptedAt onboarding { completed currentStep steps { key completed } } } errors { message path code } } }"
  end
  let(:version) { Terms::Current::VERSION }

  def accept(value = version, as: token) = gql(accept_terms, variables: { i: { version: value } }, token: as)

  def payload(body) = body.dig("data", "acceptTerms")

  def error_code(body) = body.dig("errors", 0, "extensions", "code")

  it "records the acceptance, and me shows it" do
    body = accept

    expect(payload(body)["errors"]).to eq([])
    expect(payload(body)["user"]).to include("id" => user.id, "termsVersion" => version, "termsAcceptedAt" => be_present)
    expect(gql("{ me { termsVersion termsAcceptedAt } }", token:).dig("data", "me")).to include("termsVersion" => version)
  end

  it "shows empty fields in me until the terms are accepted" do
    expect(gql("{ me { termsVersion termsAcceptedAt } }", token:).dig("data", "me")).to eq("termsVersion" => nil, "termsAcceptedAt" => nil)
  end

  it "keeps the first time when accepted again" do
    accept
    stamp = user.reload.terms_accepted_at

    expect(payload(accept)["errors"]).to eq([])
    expect(user.reload.terms_accepted_at).to eq(stamp)
  end

  describe "failures" do
    it "refuses a version that is not the current one, with the field in the path" do
      body = accept("1999-01-01")

      expect(payload(body)["user"]).to be_nil
      expect(payload(body)["errors"]).to eq([ { "message" => "Version must be the current version of the terms. Reload the terms and accept again", "path" => [ "input", "version" ], "code" => "VALIDATION_FAILED" } ])
      expect(user.reload.terms_accepted_at).to be_nil
    end

    it "says an empty version is required" do
      expect(payload(accept(""))["errors"]).to eq([ { "message" => "Version is required", "path" => [ "input", "version" ], "code" => "VALIDATION_FAILED" } ])
    end

    it "handles hostile text as plain text, never a 500" do
      [ "' OR 1=1 --", "<script>alert(1)</script>", "🔥" * 30, "x" * 5000 ].each do |value|
        expect(payload(accept(value))["errors"]).not_to be_empty
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "who may call it" do
    it "is UNAUTHENTICATED without a login, with a garbage token, or with bad input as nobody" do
      expect(error_code(accept(version, as: nil))).to eq("UNAUTHENTICATED")
      expect(error_code(accept(version, as: "garbage"))).to eq("UNAUTHENTICATED")
      expect(error_code(gql(accept_terms, variables: { i: {} }))).to eq("UNAUTHENTICATED")
    end

    it "lets every role accept for themselves" do
      User.roles.each_key do |role|
        member = create(:user, role.to_sym)

        expect(payload(accept(version, as: token_for(member)))["errors"]).to eq([])
        expect(member.reload.terms_version).to eq(version)
      end
    end

    it "has no way to name another user: the input takes only the version" do
      other = create(:user)

      [ { userId: other.id }, { termsAcceptedAt: "2020-01-01T00:00:00Z" }, { role: "SUPER_ADMIN" } ].each do |extra|
        body = gql(accept_terms, variables: { i: { version: }.merge(extra) }, token:)

        expect(body["errors"]).to be_present
      end
      expect(other.reload.terms_accepted_at).to be_nil
      expect(user.reload.terms_accepted_at).to be_nil
    end

    it "keeps each user's acceptance apart" do
      other = create(:user)
      accept

      expect(gql("{ me { termsVersion } }", token: token_for(other)).dig("data", "me", "termsVersion")).to be_nil
    end
  end

  describe "the terms step of the real registry" do
    let(:profile_input) { { firstName: "Ada", lastName: "Lovelace", dateOfBirth: "1990-05-21", phone: "+14155552671" } }
    let(:address_input) { { addressLine1: "1 Market Street", city: "San Francisco", state: "CA", postalCode: "94105", country: "US" } }
    let(:other_operation) { "mutation { requestEmailChange(input: { newEmail: \"fresh@example.test\", password: \"correct horse battery\" }) { success errors { code } } }" }

    before { stub_onboarding_steps(*real_onboarding_steps) }

    def save(operation, input) = gql("mutation($i: #{operation.camelize}Input!) { #{operation.camelize(:lower)}(input: $i) { errors { code } } }", variables: { i: input }, token:)

    it "is the last step, and acceptTerms is open through the gate" do
      expect(gql("{ me { onboarding { steps { key } } } }", token:).dig("data", "me", "onboarding", "steps").pluck("key")).to eq(%w[profile address terms])
      expect(payload(accept)["errors"]).to eq([])
    end

    it "opens the rest of the API when all three steps are done, in any order" do
      accept
      expect(error_code(gql(other_operation, token:))).to eq("ONBOARDING_REQUIRED")
      save("update_address", address_input)
      expect(error_code(gql(other_operation, token:))).to eq("ONBOARDING_REQUIRED")
      save("update_profile", profile_input)

      expect(user.onboarding_steps.pluck(:step_key)).to contain_exactly("profile", "address", "terms")
      expect(gql(other_operation, token:).dig("data", "requestEmailChange", "success")).to be(true)
    end

    it "does not block a super_admin, who has no terms step" do
      admin_token = token_for(create(:user, :super_admin))

      expect(gql("{ me { onboarding { completed steps { key } } } }", token: admin_token).dig("data", "me", "onboarding")).to eq("completed" => true, "steps" => [])
    end
  end
end
