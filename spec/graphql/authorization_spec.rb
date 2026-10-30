require "rails_helper"

RSpec.describe "Authorization", type: :request do
  let(:me) { "{ me { id email } }" }
  let(:logout) { "mutation { logout(input: {}) { success errors { message path code } } }" }
  let(:request_email_change) do
    "mutation { requestEmailChange(input: { newEmail: \"fresh@example.test\", password: \"correct horse battery\" }) { success errors { code } } }"
  end
  let(:update_profile) do
    "mutation { updateProfile(input: { firstName: \"Ada\", lastName: \"Lovelace\", dateOfBirth: \"1990-05-21\", phone: \"+14155552671\" }) { errors { code } } }"
  end
  let(:update_address) do
    "mutation { updateAddress(input: { addressLine1: \"1 Market Street\", city: \"San Francisco\", state: \"CA\", postalCode: \"94105\", country: \"US\" }) { errors { code } } }"
  end
  let(:accept_terms) { "mutation { acceptTerms(input: { version: \"#{Terms::Current::VERSION}\" }) { errors { code } } }" }
  let(:confirm_email_change) { "mutation { confirmEmailChange(input: { code: \"123456\" }) { success errors { code } } }" }

  def error_code(body)
    body.dig("errors", 0, "extensions", "code")
  end

  describe "role field" do
    let(:me_with_role) { "{ me { id role } }" }

    it "tells the frontend the role of the logged-in user" do
      expect(gql(me_with_role, token: token_for(create(:user, :super_admin))).dig("data", "me", "role")).to eq("SUPER_ADMIN")
      expect(gql(me_with_role, token: token_for(create(:user))).dig("data", "me", "role")).to eq("MEMBER")
    end

    it "comes back from signUp as MEMBER", :public_sign_up do
      body = gql("mutation($i: SignUpInput!) { signUp(input: $i) { user { role } } }",
                 variables: { i: { email: "fresh@example.test", password: "correct horse battery" } })

      expect(body.dig("data", "signUp", "user", "role")).to eq("MEMBER")
    end

    it "comes back from login" do
      create(:user, :super_admin, email: "root@example.test", password: "correct horse battery")
      body = gql("mutation($i: LoginInput!) { login(input: $i) { user { role } } }",
                 variables: { i: { email: "root@example.test", password: "correct horse battery" } })

      expect(body.dig("data", "login", "user", "role")).to eq("SUPER_ADMIN")
    end

    it "has one enum value per role in User.roles" do
      expect(Types::UserRoleEnum.values.values.map(&:value)).to match_array(User.roles.keys)
    end

    it "cannot be set by the client on signUp", :public_sign_up do
      body = gql("mutation($i: SignUpInput!) { signUp(input: $i) { token } }",
                 variables: { i: { email: "sneaky@example.test", password: "correct horse battery", role: "SUPER_ADMIN" } })

      expect(body["errors"]).to be_present
      expect(User.find_by(email: "sneaky@example.test")).to be_nil
    end
  end

  describe "role by operation" do
    User.roles.each_key do |role|
      context "as a #{role}" do
        let(:user) { create(:user, role.to_sym) }

        it "may read their own user with me" do
          expect(gql(me, token: token_for(user)).dig("data", "me", "id")).to eq(user.id)
        end

        it "may start an email change for themselves" do
          body = gql(request_email_change, token: token_for(user))

          expect(body.dig("data", "requestEmailChange", "success")).to be(true)
        end

        it "may confirm an email change for themselves (a wrong code is a normal failure, not FORBIDDEN)" do
          body = gql(confirm_email_change, token: token_for(user))

          expect(body.dig("data", "confirmEmailChange", "errors", 0, "code")).to eq("INVALID_CODE")
        end

        it "may read their own onboarding" do
          expect(gql("{ me { onboarding { completed } } }", token: token_for(user)).dig("data", "me", "onboarding", "completed")).to be(true)
        end

        it "may save their own profile" do
          body = gql(update_profile, token: token_for(user))

          expect(body.dig("data", "updateProfile", "errors")).to eq([])
          expect(user.reload.first_name).to eq("Ada")
        end

        it "may save their own address" do
          body = gql(update_address, token: token_for(user))

          expect(body.dig("data", "updateAddress", "errors")).to eq([])
          expect(user.reload.city).to eq("San Francisco")
        end

        it "may accept the terms for themselves" do
          body = gql(accept_terms, token: token_for(user))

          expect(body.dig("data", "acceptTerms", "errors")).to eq([])
          expect(user.reload.terms_version).to eq(Terms::Current::VERSION)
        end

        it "may log out" do
          body = gql(logout, token: token_for(user))

          expect(body.dig("data", "logout", "success")).to be(true)
        end
      end
    end
  end

  describe "unauthenticated" do
    it "denies me with UNAUTHENTICATED" do
      expect(error_code(gql(me))).to eq("UNAUTHENTICATED")
    end

    it "denies logout with UNAUTHENTICATED" do
      expect(error_code(gql(logout))).to eq("UNAUTHENTICATED")
    end

    it "denies updateAddress with UNAUTHENTICATED" do
      expect(error_code(gql(update_address))).to eq("UNAUTHENTICATED")
    end

    it "denies acceptTerms with UNAUTHENTICATED" do
      expect(error_code(gql(accept_terms))).to eq("UNAUTHENTICATED")
    end

    it "denies updateProfile with UNAUTHENTICATED" do
      expect(error_code(gql(update_profile))).to eq("UNAUTHENTICATED")
    end

    it "denies requestEmailChange and confirmEmailChange with UNAUTHENTICATED" do
      expect(error_code(gql(request_email_change))).to eq("UNAUTHENTICATED")
      expect(error_code(gql(confirm_email_change))).to eq("UNAUTHENTICATED")
    end
  end

  describe "authorize!" do
    let(:user) { create(:user) }
    let(:host) do
      current = user
      Class.new do
        include Authorizable

        define_method(:context) { { current_user: current } }
      end.new
    end

    def forbidden
      raise_error(GraphQL::ExecutionError) { |error| expect(error.extensions).to eq(code: "FORBIDDEN") }
    end

    it "returns the record when the policy allows" do
      expect(host.authorize!(user, :show?)).to eq(user)
    end

    it "denies when the policy says no" do
      expect { host.authorize!(create(:user), :show?) }.to forbidden
    end

    it "denies when no policy exists for the record" do
      expect { host.authorize!(Object.new, :show?) }.to forbidden
    end

    it "denies when the policy has no such method" do
      expect { host.authorize!(user, :launch_rockets?) }.to forbidden
    end

    it "denies when a policy method returns something other than true" do
      stub_const("TruthyPolicy", Class.new(ApplicationPolicy) { def show? = "yes" })
      stub_const("Truthy", Class.new)

      expect { host.authorize!(Truthy.new, :show?) }.to forbidden
    end

    it "answers UNAUTHENTICATED, not FORBIDDEN, when nobody is logged in" do
      anonymous = Class.new do
        include Authorizable

        def context = {}
      end.new

      expect { anonymous.authorize!(user, :show?) }
        .to raise_error(GraphQL::ExecutionError) { |error| expect(error.extensions).to eq(code: "UNAUTHENTICATED") }
    end

    it "never puts a class name or policy name in the message" do
      expect { host.authorize!(Object.new, :show?) }
        .to raise_error(GraphQL::ExecutionError) { |error| expect(error.message).to eq(Errors::FORBIDDEN.message) }
    end
  end

  # Default deny: every operation is public (and throttled) or has a permission test above (emailLogs and emailLog: spec/graphql/email_logs_spec.rb).
  describe "coverage" do
    let(:covered) { %w[me emailLogs emailLog logout requestEmailChange confirmEmailChange inviteUser revokeInvitation resendInvitation updateProfile updateAddress acceptTerms] }

    it "lists exactly the logged-in operations that have a permission test" do
      mutations = Types::MutationType.fields.keys.map { |name| name.camelize(:lower) }
      queries = Types::QueryType.fields.keys.map { |name| name.camelize(:lower) }

      expect((mutations + queries) - Rack::Attack::PUBLIC_OPERATIONS).to match_array(covered)
    end
  end
end
