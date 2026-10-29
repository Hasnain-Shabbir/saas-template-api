require "rails_helper"

RSpec.describe "Onboarding", type: :request do
  let(:my_onboarding) { "{ me { onboarding { completed currentStep steps { key completed completedAt } } } }" }
  let(:request_email_change) do
    "mutation { requestEmailChange(input: { newEmail: \"fresh@example.test\", password: \"correct horse battery\" }) { success errors { code } } }"
  end
  let(:user) { create(:user) }
  let(:token) { token_for(user) }

  def error_code(body) = body.dig("errors", 0, "extensions", "code")

  # The server finishes steps itself. A spec marks one done the way the server would: with a row.
  def finish(key, for_user: user) = for_user.onboarding_steps.create!(step_key: key, completed_at: Time.current)

  describe "with no steps" do
    it "reports complete, and nothing is blocked" do
      expect(gql(my_onboarding, token:).dig("data", "me", "onboarding")).to eq("completed" => true, "currentStep" => nil, "steps" => [])
      expect(gql(request_email_change, token:).dig("data", "requestEmailChange", "success")).to be(true)
    end
  end

  context "with steps" do
    let(:ready) { { value: true } }

    before do
      flag = ready
      stub_onboarding_steps(
        onboarding_step("profile", complete_when: ->(_user) { flag[:value] }),
        onboarding_step("address"),
        onboarding_step("billing", roles: %w[super_admin])
      )
    end

    describe "me { onboarding }" do
      it "lists the steps of the role in order, with the next one" do
        body = gql(my_onboarding, token:)

        expect(body.dig("data", "me", "onboarding")).to eq(
          "completed" => false, "currentStep" => "profile",
          "steps" => [ { "key" => "profile", "completed" => false, "completedAt" => nil }, { "key" => "address", "completed" => false, "completedAt" => nil } ]
        )
      end

      it "shows each role its own steps" do
        admin_keys = gql(my_onboarding, token: token_for(create(:user, :super_admin))).dig("data", "me", "onboarding", "steps").pluck("key")

        expect(admin_keys).to eq(%w[profile address billing])
        expect(gql(my_onboarding, token:).dig("data", "me", "onboarding", "steps").pluck("key")).to eq(%w[profile address])
      end

      it "never exposes the roles, the condition, or the operations of a step" do
        expect(Types::OnboardingStepType.fields.keys).to eq(%w[key completed completedAt])
        expect(Types::OnboardingType.fields.keys).to eq(%w[completed currentStep steps])
      end

      it "shows only the progress of the logged-in user" do
        finish("profile")

        other = gql(my_onboarding, token: token_for(create(:user)))
        expect(other.dig("data", "me", "onboarding", "currentStep")).to eq("profile")
        expect(gql(my_onboarding, token:).dig("data", "me", "onboarding", "currentStep")).to eq("address")
      end

      it "is UNAUTHENTICATED without a login or with a garbage token" do
        expect(error_code(gql(my_onboarding))).to eq("UNAUTHENTICATED")
        expect(error_code(gql(my_onboarding, token: "garbage"))).to eq("UNAUTHENTICATED")
      end

      it "is UNAUTHENTICATED with a token after logout" do
        gql("mutation { logout(input: {}) { success } }", token:)

        expect(error_code(gql(my_onboarding, token:))).to eq("UNAUTHENTICATED")
      end
    end

    describe "the gate" do
      it "blocks other operations until onboarding is done, with ONBOARDING_REQUIRED" do
        body = gql(request_email_change, token:)

        expect(body).to eq("data" => nil, "errors" => [ { "message" => Errors::ONBOARDING_REQUIRED.message, "extensions" => { "code" => "ONBOARDING_REQUIRED" } } ])
      end

      it "blocks before authorization and before input validation" do
        member = gql("mutation { inviteUser(input: { email: \"x@example.test\", role: MEMBER }) { success } }", token:)
        bad_input = gql("mutation { inviteUser(input: {}) { success } }", token:)

        expect(error_code(member)).to eq("ONBOARDING_REQUIRED")
        expect(error_code(bad_input)).to eq("ONBOARDING_REQUIRED")
      end

      it "does not run the operation: nothing is stored or changed" do
        gql(request_email_change, token:)

        expect(user.reload.pending_email).to be_nil
      end

      it "keeps the operations that finish onboarding open: me (with its onboarding), logout" do
        expect(gql("{ me { id } }", token:).dig("data", "me", "id")).to eq(user.id)
        expect(gql(my_onboarding, token:).dig("data", "me", "onboarding", "completed")).to be(false)
        expect(gql("mutation { logout(input: {}) { success } }", token:).dig("data", "logout", "success")).to be(true)
      end

      it "cannot be bypassed with an alias, a fragment, or by putting an open operation next to a closed one" do
        aliased = "mutation { me: requestEmailChange(input: { newEmail: \"a@example.test\", password: \"x\" }) { success } }"
        fragment = "mutation { ...F } fragment F on Mutation { requestEmailChange(input: { newEmail: \"a@example.test\", password: \"x\" }) { success } }"
        mixed = "mutation { logout(input: {}) { success } requestEmailChange(input: { newEmail: \"a@example.test\", password: \"x\" }) { success } }"

        expect([ aliased, fragment, mixed ].map { |query| error_code(gql(query, token:)) }).to all(eq("ONBOARDING_REQUIRED"))
      end

      it "opens the operations a step lists" do
        stub_onboarding_steps(onboarding_step("profile", operations: %w[requestEmailChange]))

        expect(gql(request_email_change, token:).dig("data", "requestEmailChange", "success")).to be(true)
      end

      it "stops blocking when the last step is done" do
        finish("profile")
        expect(error_code(gql(request_email_change, token:))).to eq("ONBOARDING_REQUIRED")

        finish("address")
        expect(gql(request_email_change, token:).dig("data", "requestEmailChange", "success")).to be(true)
      end

      it "does not block a role that has no steps" do
        stub_onboarding_steps(onboarding_step("profile", roles: %w[member]))
        admin_token = token_for(create(:user, :super_admin))

        expect(gql(request_email_change, token: admin_token).dig("data", "requestEmailChange", "success")).to be(true)
        expect(error_code(gql(request_email_change, token:))).to eq("ONBOARDING_REQUIRED")
      end

      it "blocks a new step at once for a user who is already logged in" do
        stub_onboarding_steps
        expect(gql(request_email_change, token:).dig("data", "requestEmailChange", "success")).to be(true)

        stub_onboarding_steps(onboarding_step("terms"))
        expect(error_code(gql(request_email_change, token:))).to eq("ONBOARDING_REQUIRED")
      end

      it "answers nobody with UNAUTHENTICATED first, not ONBOARDING_REQUIRED" do
        expect(error_code(gql(request_email_change))).to eq("UNAUTHENTICATED")
      end

      it "does not stop a public operation" do
        create(:user, email: "someone@example.test", password: "correct horse battery")
        body = gql("mutation($i: LoginInput!) { login(input: $i) { token errors { code } } }", variables: { i: { email: "someone@example.test", password: "correct horse battery" } })

        expect(body.dig("data", "login", "token")).to be_present
      end
    end
  end
end
