# The one place for error codes and client messages. Use these constants, never inline strings.
# A typo in a name raises NameError, so a wrong code cannot reach a client.
# Messages are safe for end users: no class names, SQL, paths, or ids.
module Errors
  Error = Data.define(:code, :message)

  UNAUTHENTICATED = Error.new(code: "UNAUTHENTICATED", message: "Authentication required")
  FORBIDDEN = Error.new(code: "FORBIDDEN", message: "You are not allowed to do this")
  INVALID_CREDENTIALS = Error.new(code: "INVALID_CREDENTIALS", message: "Invalid email or password")
  INVALID_CODE = Error.new(code: "INVALID_CODE", message: "This code is invalid or has expired")
  VALIDATION_FAILED =Error.new(code: "VALIDATION_FAILED", message: "Validation failed")
  FIELD_REQUIRED = Error.new(code: "VALIDATION_FAILED", message: "is required")
  FIELD_INVALID = Error.new(code: "VALIDATION_FAILED", message: "is invalid")
  BAD_REQUEST = Error.new(code: "BAD_REQUEST", message: "Invalid request")
  RATE_LIMITED = Error.new(code: "RATE_LIMITED", message: "Too many requests")
  INTERNAL_ERROR = Error.new(code: "INTERNAL_ERROR", message: "Something went wrong")

  # Top-level GraphQL error: { message, extensions: { code } }.
  def self.execution_error(error)
    GraphQL::ExecutionError.new(error.message, extensions: { code: error.code })
  end

  # The JSON body of an error sent outside GraphQL execution (HTTP 400, 429). Same shape as every other error.
  def self.response_body(error)
    { errors: [ { message: error.message, extensions: { code: error.code } } ] }
  end

  # Failed Result for a service. `errors` carries the model's validation errors, if any.
  def self.failure(error, errors: nil)
    Result.failure(code: error.code, message: error.message, errors:)
  end
end
