class Rack::Attack
  # Queries an anonymous caller can reach. They have their own limit, because a page may check on every load.
  PUBLIC_QUERIES = %w[invitationStatus].freeze
  # Operations an anonymous caller can reach: the mutations that override `ready?`, and the public queries. A spec fails if this list drifts.
  PUBLIC_OPERATIONS = (%w[login verifyLoginCode signUp requestPasswordReset resetPassword acceptInvitation] + PUBLIC_QUERIES).freeze
  # Logged-in mutations that check a password or guess a code. Limited like public ones (per IP: the middleware runs before Warden,
  # and a token is never decoded without verification). A spec fails if one is missing.
  EMAIL_CHANGE_OPERATIONS = %w[requestEmailChange confirmEmailChange].freeze
  # Logged-in mutations that send an invitation email or look one up by address. Limited per IP like the email change.
  INVITATION_OPERATIONS = %w[inviteUser resendInvitation revokeInvitation].freeze
  # Logged-in mutations that block or restore a user. Limited per IP like the invitations (a stolen admin token could lock out many users).
  ARCHIVE_OPERATIONS = %w[archiveUser unarchiveUser].freeze
  MAX_BODY_BYTES =100 * 1024

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

  # Names of the fields in the query, counted from the parsed query (aliases and fragments cannot hide one).
  def self.field_names(req)
    query = graphql_params(req)["query"]
    return [] unless query.is_a?(String)

    req.env["saas_template_api.field_names"] ||=
      collect_field_names(GraphQL.parse(query, max_tokens: SaasTemplateApiSchema.max_query_string_tokens))
  rescue GraphQL::ParseError
    [] # the schema rejects it with BAD_REQUEST
  end

  def self.public_operations(req)
    field_names(req).select { |name| PUBLIC_OPERATIONS.include?(name) }
  end

  def self.email_change_operations(req)
    field_names(req).select { |name| EMAIL_CHANGE_OPERATIONS.include?(name) }
  end

  def self.invitation_operations(req)
    field_names(req).select { |name| INVITATION_OPERATIONS.include?(name) }
  end

  def self.archive_operations(req)
    field_names(req).select { |name| ARCHIVE_OPERATIONS.include?(name) }
  end

  def self.collect_field_names(node)
    own = node.is_a?(GraphQL::Language::Nodes::Field) ? [ node.name ] : []
    own + node.children.flat_map { |child| collect_field_names(child) }
  end

  blocklist("graphql/oversized-body") { |req| req.post? && req.path == "/graphql" && req.content_length.to_i > MAX_BODY_BYTES }

  # One HTTP request must not carry several public operations: aliases would multiply password guesses.
  blocklist("graphql/batched-public-operations") { |req| public_operations(req).size > 1 }

  # Same reason for the email change: aliases would multiply password and code guesses.
  blocklist("graphql/batched-email-change-operations") { |req| email_change_operations(req).size > 1 }

  # Aliases would multiply invitation emails.
  blocklist("graphql/batched-invitation-operations") { |req| invitation_operations(req).size > 1 }

  # Aliases would archive many users in one request.
  blocklist("graphql/batched-archive-operations") { |req| archive_operations(req).size > 1 }

  # Per IP, for every public mutation.
  throttle("public-operations/ip", limit: 10, period: 1.minute) do |req|
    req.ip if (public_operations(req) - PUBLIC_QUERIES).any?
  end

  # Per IP, for the public queries (token guesses and probing). Apart from the mutations, so a page load never costs a login.
  throttle("public-queries/ip", limit: 20, period: 1.minute) do |req|
    req.ip if (public_operations(req) & PUBLIC_QUERIES).any?
  end

  # Per IP, account creation spam.
  throttle("sign-up/ip", limit: 20, period: 1.hour) do |req|
    req.ip if public_operations(req).include?("signUp")
  end

  # Per IP, mail and guess abuse of the email change (the code itself also dies after 5 wrong guesses).
  throttle("email-change/ip", limit: 10, period: 1.hour) do |req|
    req.ip if email_change_operations(req).any?
  end

  # Per IP, invitation mail abuse (for example with a stolen admin token).
  throttle("invitations/ip", limit: 30, period: 1.hour) do |req|
    req.ip if invitation_operations(req).any?
  end

  # Per IP, blocking and restoring users (for example with a stolen admin token).
  throttle("archive/ip", limit: 30, period: 1.hour) do |req|
    req.ip if archive_operations(req).any?
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
