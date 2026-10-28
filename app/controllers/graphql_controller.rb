class GraphqlController < ApplicationController
  class InvalidRequest < StandardError; end

  rescue_from InvalidRequest, with: :render_bad_request

  before_action :require_json
  before_action :reject_null_bytes

  def execute
    query = params[:query]
    operation_name = params[:operationName]
    raise InvalidRequest unless query.is_a?(String) && (operation_name.nil? || operation_name.is_a?(String))

    context = {
      current_user: current_user,
      token: bearer_token
    }
    result = SaasTemplateApiSchema.execute(query, variables: prepare_variables(params[:variables]), context: context, operation_name: operation_name)
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

  def current_user
    request.env["warden"]&.authenticate(scope: :user)
  end
end
