require "rails_helper"

RSpec.describe "CORS" do
  let(:allowed_origin) { ENV.fetch("FRONTEND_URL", "http://localhost:3000") }

  def preflight(origin)
    process :options, "/graphql", headers: {
      "Origin" => origin,
      "Access-Control-Request-Method" => "POST"
    }
  end

  it "allows the configured frontend origin" do
    preflight(allowed_origin)

    expect(response.headers["Access-Control-Allow-Origin"]).to eq(allowed_origin)
  end

  it "does not allow any other origin" do
    preflight("https://evil.example")

    expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
  end
end
