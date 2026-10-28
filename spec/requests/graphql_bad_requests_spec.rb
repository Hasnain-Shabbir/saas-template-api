require "rails_helper"

RSpec.describe "Malformed GraphQL requests", type: :request do
  let(:bad_request_body) { Errors.response_body(Errors::BAD_REQUEST).deep_stringify_keys }
  let(:json) { { "Content-Type" => "application/json" } }

  def post_json(body)
    post "/graphql", params: body, headers: json
  end

  def expect_bad_request
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body).to eq(bad_request_body)
  end

  it "answers 400, never 500, when variables are not valid JSON" do
    post_json({ query: "{ me { id } }", variables: "{not json" }.to_json)

    expect_bad_request
  end

  it "answers 400 when variables are an array, a number, or a JSON array string" do
    [ [ 1, 2 ], 12_345, "[1,2]" ].each do |variables|
      post_json({ query: "{ me { id } }", variables: }.to_json)

      expect_bad_request
    end
  end

  it "answers 400 when the query is an array or an object" do
    [ [ "{ me { id } }" ], { a: 1 }, 5 ].each do |query|
      post_json({ query: }.to_json)

      expect_bad_request
    end
  end

  it "answers 400 when the query is missing" do
    post_json({}.to_json)

    expect_bad_request
  end

  it "answers 400 when operationName is not a string" do
    post_json({ query: "{ me { id } }", operationName: { a: 1 } }.to_json)

    expect_bad_request
  end

  it "accepts variables sent as a JSON string, null, or an empty string" do
    [ "{}", "null", "" ].each do |variables|
      post_json({ query: "{ __typename }", variables: }.to_json)

      expect(response).to have_http_status(:ok)
    end
  end

  it "answers 400 for a NUL byte in any string (PostgreSQL cannot store it)" do
    [ "a\u0000b@example.test", "pass\u0000word long" ].each do |value|
      expect { post_json({ query: "mutation($i: LoginInput!) { login(input: $i) { token } }", variables: { i: { email: value, password: value } } }.to_json) }
        .not_to raise_error

      expect_bad_request
    end
  end

  it "answers 400 for a NUL byte written inside the query text" do
    post_json({ query: "mutation { login(input: { email: \"a\\u0000b\", password: \"x\" }) { token } }" }.to_json)

    expect_bad_request
  end

  it "rejects a form-encoded body" do
    post "/graphql", params: "query=%7B+__typename+%7D", headers: { "Content-Type" => "application/x-www-form-urlencoded" }

    expect_bad_request
  end

  it "rejects a text/plain body" do
    post "/graphql", params: "{ __typename }", headers: { "Content-Type" => "text/plain" }

    expect_bad_request
  end

  it "does not serve GET or PUT" do
    get "/graphql", params: { query: "{ __typename }" }
    expect(response).to have_http_status(:not_found)

    put "/graphql", params: { query: "{ __typename }" }, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it "never puts an exception message or class name in the body" do
    post_json({ query: "{ me { id } }", variables: "{not json" }.to_json)

    expect(response.body).not_to match(/JSON|ParserError|ArgumentError|expected object key/)
  end
end
