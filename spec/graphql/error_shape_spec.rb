require "rails_helper"

# Every top-level error reaches the client as { message, path, extensions: { code } }.
RSpec.describe "GraphQL error shape", type: :request do
  let(:login) { "mutation Login($input: LoginInput!) { login(input: $input) { token } }" }

  it "answers a missing variable with VALIDATION_FAILED per field and no sent value" do
    body = gql(login, variables: { input: { email: nil, password: nil } })

    expect(body["errors"]).to contain_exactly(
      { "message" => "email is required", "path" => [ "input", "email" ], "extensions" => { "code" => "VALIDATION_FAILED" } },
      { "message" => "password is required", "path" => [ "input", "password" ], "extensions" => { "code" => "VALIDATION_FAILED" } }
    )
  end

  it "answers an unknown field with BAD_REQUEST" do
    body = gql("query { doesNotExist }", token: token_for(create(:user)))

    expect(body["errors"]).to all(match("path" => a_kind_of(Array), "message" => a_kind_of(String), "extensions" => { "code" => "BAD_REQUEST" }))
  end

  it "answers a syntax error with BAD_REQUEST" do
    body = gql("query {")

    expect(body["errors"]).to all(include("extensions" => { "code" => "BAD_REQUEST" }))
  end
end
