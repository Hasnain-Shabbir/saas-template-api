require "rails_helper"

RSpec.describe "Log filtering" do
  let(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  it "filters credentials written inline in the GraphQL query text" do
    params = { "query" => 'mutation { login(input: { email: "a@example.test", password: "s3cret-pass" }) { token } }' }

    expect(filter.filter(params).to_s).not_to include("s3cret-pass", "a@example.test")
  end

  it "filters variables sent as a JSON string" do
    params = { "variables" => '{"input":{"password":"s3cret-pass"}}' }

    expect(filter.filter(params).to_s).not_to include("s3cret-pass")
  end

  it "filters variables sent as an object" do
    params = { "variables" => { "input" => { "email" => "a@example.test", "password" => "s3cret-pass" } } }

    expect(filter.filter(params).to_s).not_to include("s3cret-pass", "a@example.test")
  end

  it "filters the same values under the wrapped graphql key" do
    params = { "graphql" => { "query" => 'mutation { login(input: { password: "s3cret-pass" }) { token } }' } }

    expect(filter.filter(params).to_s).not_to include("s3cret-pass")
  end

  it "keeps a query without inline values readable" do
    params = { "query" => "{ me { id } }" }

    expect(filter.filter(params)).to eq(params)
  end
end
