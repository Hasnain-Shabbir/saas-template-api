require "rails_helper"

RSpec.describe GraphqlErrorNormalizer do
  def normalize(errors) = described_class.call({ "errors" => errors })["errors"]

  it "leaves a response without errors alone" do
    expect(described_class.call({ "data" => { "a" => 1 } })).to eq("data" => { "a" => 1 })
  end

  it "turns a bad variable into one VALIDATION_FAILED error per field, without the sent value" do
    error = {
      "message" => "Variable $input of type LoginInput! was provided invalid value for email (Expected value to not be null)",
      "locations" => [ { "line" => 1, "column" => 16 } ],
      "extensions" => {
        "value" => { "email" => nil, "password" => "hunter2" },
        "problems" => [
          { "path" => [ "email" ], "explanation" => "Expected value to not be null" },
          { "path" => [ "password" ], "explanation" => "Could not coerce value 123 to String" }
        ]
      }
    }

    result = normalize([ error ])

    expect(result).to eq([
      { "message" => "email is required", "path" => [ "input", "email" ], "extensions" => { "code" => "VALIDATION_FAILED" } },
      { "message" => "password is invalid", "path" => [ "input", "password" ], "extensions" => { "code" => "VALIDATION_FAILED" } }
    ])
    expect(result.to_s).not_to include("hunter2")
    expect(result.to_s).not_to include("123")
  end

  it "keeps the message and code of an error that already has one of our codes" do
    error = { "message" => "Authentication required", "locations" => [], "path" => [ "logout" ], "extensions" => { "code" => "UNAUTHENTICATED" } }

    expect(normalize([ error ])).to eq([
      { "message" => "Authentication required", "path" => [ "logout" ], "extensions" => { "code" => "UNAUTHENTICATED" } }
    ])
  end

  it "gives a query error BAD_REQUEST and drops schema detail from extensions" do
    error = { "message" => "Field 'foo' doesn't exist on type 'Query'", "path" => [], "extensions" => { "code" => "undefinedField", "typeName" => "Query" } }

    expect(normalize([ error ])).to eq([
      { "message" => "Field 'foo' doesn't exist on type 'Query'", "path" => [], "extensions" => { "code" => "BAD_REQUEST" } }
    ])
  end

  it "hides the message of a query error outside development and test" do
    allow(Rails.env).to receive(:local?).and_return(false)
    error = { "message" => "Field 'foo' doesn't exist on type 'Query'", "extensions" => { "code" => "undefinedField" } }

    expect(normalize([ error ])).to eq([
      { "message" => "Invalid request", "path" => [], "extensions" => { "code" => "BAD_REQUEST" } }
    ])
  end

  it "gives an error with no extensions BAD_REQUEST and an empty path" do
    expect(normalize([ { "message" => "Parse error" } ])).to eq([
      { "message" => "Parse error", "path" => [], "extensions" => { "code" => "BAD_REQUEST" } }
    ])
  end
end
