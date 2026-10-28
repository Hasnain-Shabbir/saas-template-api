require "rails_helper"

RSpec.describe "Rate limiting and request guards", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:login) { "mutation($input: LoginInput!) { login(input: $input) { token errors { code } } }" }
  let(:sign_up) { "mutation($input: SignUpInput!) { signUp(input: $input) { token errors { code } } }" }
  let(:wrong_login) { { input: { email: "nobody@example.test", password: "wrong password 1" } } }

  around do |example|
    original = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rack::Attack.cache.store = original
  end

  def expect_error(status, code)
    expect(response).to have_http_status(status)
    expect(response.parsed_body).to eq("errors" => [ { "message" => Errors.const_get(code).message, "extensions" => { "code" => code.to_s } } ])
  end

  describe "public operations" do
    it "allows 10 per minute per IP, then answers 429 RATE_LIMITED with retry-after" do
      10.times { gql(login, variables: wrong_login) }
      expect(response).to have_http_status(:ok)

      gql(login, variables: wrong_login)

      expect_error(:too_many_requests, :RATE_LIMITED)
      expect(response.headers["retry-after"]).to eq("60")
    end

    it "starts again after the period" do
      11.times { gql(login, variables: wrong_login) }
      travel 61.seconds

      gql(login, variables: wrong_login)

      expect(response).to have_http_status(:ok)
    end

    it "does not throttle an authenticated query" do
      token = token_for(create(:user))

      15.times { gql("{ me { id } }", token:) }

      expect(response).to have_http_status(:ok)
    end

    it "caps account creation per IP per hour" do
      2.times do |round|
        10.times { |i| gql(sign_up, variables: { input: { email: "r#{round}x#{i}@example.test", password: "a long password" } }) }
        travel 61.seconds
      end

      gql(sign_up, variables: { input: { email: "last@example.test", password: "a long password" } })

      expect_error(:too_many_requests, :RATE_LIMITED)
    end
  end

  describe "email change operations" do
    let(:user) { create(:user, password: "correct horse battery") }
    let(:token) { token_for(user) }
    let(:request_change) { "mutation($input: RequestEmailChangeInput!) { requestEmailChange(input: $input) { success errors { code } } }" }
    let(:confirm_change) { "mutation($input: ConfirmEmailChangeInput!) { confirmEmailChange(input: $input) { success errors { code } } }" }
    let(:guess) { { input: { code: "000000" } } }

    it "allows 10 per hour per IP, across both operations, then answers 429 RATE_LIMITED with retry-after" do
      10.times { gql(confirm_change, variables: guess, token:) }
      expect(response).to have_http_status(:ok)

      gql(request_change, variables: { input: { newEmail: "fresh@example.test", password: "correct horse battery" } }, token:)

      expect_error(:too_many_requests, :RATE_LIMITED)
      expect(response.headers["retry-after"]).to eq("3600")
    end

    it "starts again after the period" do
      11.times { gql(confirm_change, variables: guess, token:) }
      travel 61.minutes

      gql(confirm_change, variables: guess, token:)

      expect(response).to have_http_status(:ok)
    end

    it "blocks several email change operations in one request (aliases multiply guesses)" do
      gql("mutation { a: confirmEmailChange(input: { code: \"000000\" }) { success } b: confirmEmailChange(input: { code: \"111111\" }) { success } }", token:)

      expect_error(:bad_request, :BAD_REQUEST)
    end

    it "does not count other operations" do
      11.times { gql("{ me { id } }", token:) }

      expect(response).to have_http_status(:ok)
    end

    it "lists every logged-in mutation that checks a password or a code" do
      expect(Rack::Attack::EMAIL_CHANGE_OPERATIONS).to match_array(%w[requestEmailChange confirmEmailChange])
      expect(Types::MutationType.fields.keys.map { |name| name.camelize(:lower) }).to include(*Rack::Attack::EMAIL_CHANGE_OPERATIONS)
    end
  end

  describe "batching" do
    it "blocks several public operations in one request (aliases)" do
      gql("mutation { a: login(input: { email: \"a@example.test\", password: \"x\" }) { token } b: login(input: { email: \"a@example.test\", password: \"y\" }) { token } }")

      expect_error(:bad_request, :BAD_REQUEST)
    end

    it "blocks them when hidden behind a fragment" do
      gql(<<~GQL)
        fragment F on Mutation { login(input: { email: "a@example.test", password: "x" }) { token } }
        mutation { ...F signUp(input: { email: "a@example.test", password: "y" }) { token } }
      GQL

      expect_error(:bad_request, :BAD_REQUEST)
    end

    it "does not run the operations that were blocked" do
      expect { gql("mutation { a: signUp(input: { email: \"a@example.test\", password: \"a long password\" }) { token } b: signUp(input: { email: \"b@example.test\", password: \"a long password\" }) { token } }") }
        .not_to change(User, :count)
    end
  end

  describe "body size" do
    it "blocks a body over 100 KB before it is parsed" do
      post "/graphql", params: { query: "{ me { id } }", pad: "x" * (Rack::Attack::MAX_BODY_BYTES + 1) }, as: :json

      expect_error(:bad_request, :BAD_REQUEST)
    end
  end

  # Default deny: a mutation that skips login (overrides ready?) is public, so it must be throttled.
  describe "coverage" do
    it "lists exactly the mutations that do not require login" do
      public_mutations = Types::MutationType.fields.values.select do |field|
        field.mutation.instance_method(:ready?).owner != Mutations::BaseMutation
      end

      expect(public_mutations.map(&:graphql_name)).to match_array(Rack::Attack::PUBLIC_OPERATIONS)
    end
  end
end
