class Rack::Attack
  # Mutations an anonymous caller can reach (the ones that override `ready?`). A spec fails if this list drifts.
  PUBLIC_OPERATIONS = %w[login signUp requestPasswordReset resetPassword].freeze
  MAX_BODY_BYTES = 100 * 1024

  # Parse the GraphQL POST body once per request and remember it in the Rack env.
  def self.graphql_params(req)
    return {} unless req.post? && req.path == "/graphql" && req.media_type == "application/json"

    req.env["saas_template_api.graphql_params"] ||= begin
      body = req.body.read
      req.body.rewind # Rails must still be able to read the body after us
      parsed = JSON.parse(body)
      parsed.is_a?(Hash) ? parsed : {}
    end
  rescue JSON::ParserError
    req.env["saas_template_api.graphql_params"] = {}
  end

  # Names of the public operations in the query, counted from the parsed query (aliases and fragments cannot hide one).
  def self.public_operations(req)
    query = graphql_params(req)["query"]
    return [] unless query.is_a?(String)

    req.env["saas_template_api.public_operations"] ||=
      collect_public_operations(GraphQL.parse(query, max_tokens: SaasTemplateApiSchema.max_query_string_tokens))
  rescue GraphQL::ParseError
    [] # the schema rejects it with BAD_REQUEST
  end

  def self.collect_public_operations(node)
    own = node.is_a?(GraphQL::Language::Nodes::Field) && PUBLIC_OPERATIONS.include?(node.name) ? [ node.name ] : []
    own + node.children.flat_map { |child| collect_public_operations(child) }
  end

  blocklist("graphql/oversized-body") { |req| req.post? && req.path == "/graphql" && req.content_length.to_i > MAX_BODY_BYTES }

  # One HTTP request must not carry several public operations: aliases would multiply password guesses.
  blocklist("graphql/batched-public-operations") { |req| public_operations(req).size > 1 }

  # Per IP, for everything an anonymous caller can reach.
  throttle("public-operations/ip", limit: 10, period: 1.minute) do |req|
    req.ip if public_operations(req).any?
  end

  # Per IP, account creation spam.
  throttle("sign-up/ip", limit: 20, period: 1.hour) do |req|
    req.ip if public_operations(req).include?("signUp")
  end

  self.blocklisted_responder = lambda do |_req|
    [ 400, { "content-type" => "application/json" }, [ Errors.response_body(Errors::BAD_REQUEST).to_json ] ]
  end

  self.throttled_responder = lambda do |req|
    retry_after = (req.env["rack.attack.match_data"] || {})[:period].to_i
    [ 429, { "content-type" => "application/json", "retry-after" => retry_after.to_s },
      [ Errors.response_body(Errors::RATE_LIMITED).to_json ] ]
  end
end
