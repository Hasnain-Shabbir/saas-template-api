class GraphqlController < ApplicationController
  class InvalidRequest < StandardError; end

  rescue_from InvalidRequest, with: :render_bad_request

  before_action :require_json
  before_action :reject_null_bytes

  def execute
    query = params[:query]
    operation_name = params[:operationName]
    raise InvalidRequest unless query.is_a?(String) && (operation_name.nil? || operation_name.is_a?(String))

    variables = prepare_variables(params[:variables]) # the request envelope: a malformed one is BAD_REQUEST for everybody
    user = current_user
    Audit.actor = user.id if user
    # Authentication comes before everything GraphQL checks (arguments, enums, variables): nobody logged in gets UNAUTHENTICATED only.
    return render json: { data: nil }.merge(Errors.response_body(Errors::UNAUTHENTICATED)) if user.nil? && AuthGate.login_required?(query, operation_name:)

    # Then onboarding: a user with steps left can only reach the operations that let them finish (and log out).
    return render json: { data: nil }.merge(Errors.response_body(Errors::ONBOARDING_REQUIRED)) if user && OnboardingGate.blocked?(user, query, operation_name:)

    context = {
      current_user: user,
      token: bearer_token,
      request_id: request.request_id # stored next to a read audit row
    }
    result = SaasTemplateApiSchema.execute(query, variables:, context: context, operation_name: operation_name)
    render json: GraphqlErrorNormalizer.call(result.to_h)
  end

  private

  def require_json
    raise InvalidRequest unless request.media_type == "application/json"
  end

  def reject_null_bytes
    raise InvalidRequest if request.raw_post.match?(ValidationRules::NULL_BYTE)
  end

  def render_bad_request
    render json: Errors.response_body(Errors::BAD_REQUEST), status: :bad_request
  end

  # Anything that is not an object (or a JSON string holding an object) is a bad request, never a 500.
  def prepare_variables(variables_param)
    case variables_param
    when nil then {}
    when ActionController::Parameters then variables_param.to_unsafe_hash # GraphQL-Ruby validates name and type of incoming variables.
    when String then parse_variables(variables_param)
    else raise InvalidRequest
    end
  end

  def parse_variables(json)
    return {} if json.blank?

    parsed = JSON.parse(json)
    raise InvalidRequest unless parsed.nil? || parsed.is_a?(Hash)

    parsed || {}
  rescue JSON::ParserError
    raise InvalidRequest
  end

  def bearer_token
    header = request.authorization.to_s
    header.delete_prefix("Bearer ").presence if header.start_with?("Bearer ")
  end

  # For a locked account Devise does `throw :warden`, and Warden's middleware answers with its own 401 (a different shape, and it
  # names the lock). Catch the throw here: the token of a locked account then gets the same UNAUTHENTICATED as a garbage token.
  # `catch` returns the thrown hash, so a throw must never be taken for a user.
  def current_user
    user = nil
    authenticated = false
    catch(:warden) do
      user = request.env["warden"]&.authenticate(scope: :user)
      authenticated = true
    end
    authenticated ? user : nil
  end
end
