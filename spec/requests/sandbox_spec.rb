require "rails_helper"

RSpec.describe "GraphQL sandbox" do
  it "is not mounted outside development" do
    get "/sandbox"

    expect(response).to have_http_status(:not_found)
  end
end
