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

  it "filters a one-time code sent as a variable object" do
    params = { "variables" => { "input" => { "email" => "a@example.test", "code" => "482913", "password" => "s3cret-pass" } } }

    expect(filter.filter(params).to_s).not_to include("482913", "s3cret-pass")
  end

  it "filters a one-time code under the wrapped graphql key, and a plain code parameter" do
    wrapped = { "graphql" => { "variables" => { "input" => { "code" => "482913" } } } }

    expect(filter.filter(wrapped).to_s).not_to include("482913")
    expect(filter.filter({ "code" => "482913" }).to_s).not_to include("482913")
  end

  it "filters the same values under the wrapped graphql key" do
    params = { "graphql" => { "query" => 'mutation { login(input: { password: "s3cret-pass" }) { token } }' } }

    expect(filter.filter(params).to_s).not_to include("s3cret-pass")
  end

  it "filters the profile fields, in snake_case and in the camelCase of GraphQL variables" do
    values = %w[Ada Lovelace 1815-12-10 +14155552671]
    camel = { "variables" => { "input" => { "firstName" => "Ada", "lastName" => "Lovelace", "dateOfBirth" => "1815-12-10", "phone" => "+14155552671" } } }
    snake = { "first_name" => "Ada", "last_name" => "Lovelace", "date_of_birth" => "1815-12-10", "phone" => "+14155552671" }

    expect(filter.filter(camel).to_s).not_to include(*values)
    expect(filter.filter(snake).to_s).not_to include(*values)
  end

  it "filters a profile written inline in the query text" do
    params = { "query" => 'mutation { updateProfile(input: { firstName: "Ada", phone: "+14155552671" }) { errors { code } } }' }

    expect(filter.filter(params).to_s).not_to include("Ada", "+14155552671")
  end

  it "filters the address fields, in snake_case and in the camelCase of GraphQL variables" do
    values = [ "1 Market Street", "Suite 4", "San Francisco", "94105" ]
    camel = { "variables" => { "input" => { "addressLine1" => values[0], "addressLine2" => values[1], "city" => values[2], "state" => "CA", "postalCode" => values[3] } } }
    snake = { "address_line_1" => values[0], "address_line_2" => values[1], "city" => values[2], "state" => "CA", "postal_code" => values[3] }

    expect(filter.filter(camel).to_s).not_to include(*values)
    expect(filter.filter(snake).to_s).not_to include(*values)
  end

  it "keeps a query without inline values readable" do
    params = { "query" => "{ me { id } }" }

    expect(filter.filter(params)).to eq(params)
  end
end
