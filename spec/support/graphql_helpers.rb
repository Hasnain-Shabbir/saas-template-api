module GraphqlHelpers
  # Sends one GraphQL request, the way a client does: JSON body, token in the Authorization header.
  def gql(query, variables: {}, token: nil)
    headers = token ? { "Authorization" => "Bearer #{token}" } : {}
    post "/graphql", params: { query:, variables: }, headers:, as: :json
    response.parsed_body
  end

  def token_for(user)
    Auth::IssueToken.call(user)
  end
end

RSpec.configure do |config|
  config.include GraphqlHelpers, type: :request
end
