# Gives every top-level GraphQL error one shape: { message, path, extensions: { code } }.
# Payload errors (`errors { message path code }`) already match it, so a client needs one handler.
#
# Why: GraphQL-Ruby builds top-level errors in several shapes (bad variables, syntax, unknown
# field, ExecutionError). Some echo the sent value (`extensions.value`) or schema names.
# Errors that already carry one of our codes (UPPER_SNAKE) keep their message and code.
class GraphqlErrorNormalizer
  OUR_CODE = /\A[A-Z][A-Z_]*\z/
  VARIABLE_NAME = /\AVariable \$(\w+)/
  NULL_EXPLANATION = "Expected value to not be null"

  def self.call(result_hash)
    errors = result_hash["errors"]
    return result_hash if errors.blank?

    result_hash.merge("errors" => errors.flat_map { |error| new(error).normalize })
  end

  def initialize(error)
    @error = error
  end

  def normalize
    extensions = @error["extensions"] || {}
    return variable_errors(extensions["problems"]) if extensions["problems"]

    code = extensions["code"].to_s
    return [ build(@error["message"], @error["path"], code) ] if code.match?(OUR_CODE)

    [ build(safe_message, @error["path"], Errors::BAD_REQUEST.code) ]
  end

  private

  # One error per invalid field. The sent value (`extensions.value`) is dropped: it can hold a password.
  def variable_errors(problems)
    variable = @error["message"].to_s[VARIABLE_NAME, 1]

    problems.map do |problem|
      path = [ variable, *problem["path"] ].compact.map(&:to_s)
      field_error = problem["explanation"] == NULL_EXPLANATION ? Errors::FIELD_REQUIRED : Errors::FIELD_INVALID
      build("#{path.last} #{field_error.message}", path, field_error.code)
    end
  end

  # Syntax and unknown-field messages name schema parts. Only show them where introspection is on.
  def safe_message
    Rails.env.local? ? @error["message"] : Errors::BAD_REQUEST.message
  end

  def build(message, path, code)
    { "message" => message, "path" => Array(path), "extensions" => { "code" => code } }
  end
end
