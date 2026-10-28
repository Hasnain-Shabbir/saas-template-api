# frozen_string_literal: true

class GraphqlController < ApplicationController
  def execute
    variables = prepare_variables(params[:variables])
    query = params[:query]
    operation_name = params[:operationName]
    context = {
      current_user: current_user,
      token: bearer_token
    }
    result = SaasTemplateApiSchema.execute(query, variables: variables, context: context, operation_name: operation_name)
    render json: GraphqlErrorNormalizer.call(result.to_h)
  end

  private

  # Handle variables in form data, JSON body, or a blank value
  def prepare_variables(variables_param)
    case variables_param
    when String
      if variables_param.present?
        JSON.parse(variables_param) || {}
      else
        {}
      end
    when Hash
      variables_param
    when ActionController::Parameters
      variables_param.to_unsafe_hash # GraphQL-Ruby will validate name and type of incoming variables.
    when nil
      {}
    else
      # No value in the message: variables can hold credentials.
      raise ArgumentError, "Unexpected variables parameter"
    end
  end

  def bearer_token
    header = request.authorization.to_s
    header.delete_prefix("Bearer ").presence if header.start_with?("Bearer ")
  end

  # Warden's jwt strategy checks the signature, the expiry, and the allowlist.
  # Any failure gives nil, and the operation then answers UNAUTHENTICATED.
  def current_user
    request.env["warden"]&.authenticate(scope: :user)
  end
end
