# The one place for error codes and client messages. Use these constants, never inline strings.
# A typo in a name raises NameError, so a wrong code cannot reach a client.
# Messages are safe for end users: no class names, SQL, paths, or ids.
module Errors
  Error = Data.define(:code, :message)

  UNAUTHENTICATED = Error.new(code: "UNAUTHENTICATED", message: "Authentication required")
  FORBIDDEN = Error.new(code: "FORBIDDEN", message: "You are not allowed to do this")
  SIGN_UP_DISABLED = Error.new(code: "FORBIDDEN", message: "Sign up is closed to the public. Ask an administrator to send you an invitation")
  INVALID_CREDENTIALS = Error.new(code: "INVALID_CREDENTIALS", message: "Invalid email or password")
  ACCOUNT_ARCHIVED = Error.new(code: "ACCOUNT_ARCHIVED", message: "Your access has been blocked. Contact an administrator")
  ACCESS_REVOKED = Error.new(code: "ACCESS_REVOKED", message: "Your access has been revoked. Contact an administrator")
  INVALID_CODE =Error.new(code: "INVALID_CODE", message: "This code is invalid or has expired")
  INVALID_INVITATION = Error.new(code: "INVALID_INVITATION", message: "This invitation is invalid or has expired")
  IMPERSONATE_SUPER_ADMIN = Error.new(code: "FORBIDDEN", message: "Super admins cannot be impersonated. Only members can")
  IMPERSONATE_BLOCKED_USER = Error.new(code: "FORBIDDEN", message: "This user is archived or has no access, so they cannot be impersonated. Restore their access first")
  NOT_ALLOWED_WHILE_IMPERSONATING = Error.new(code: "FORBIDDEN", message: "You cannot do this while impersonating a user. Stop the impersonation first")
  NOT_IMPERSONATING = Error.new(code: "NOT_IMPERSONATING", message: "You are not impersonating anyone. Send this with the token of an impersonation session")
  IMPERSONATION_ACTIVE = Error.new(code: "IMPERSONATION_ACTIVE", message: "You already have an impersonation open. Stop it before you start another")
  NOT_FOUND = Error.new(code: "NOT_FOUND", message: "Not found")
  ONBOARDING_REQUIRED = Error.new(code: "ONBOARDING_REQUIRED", message: "Complete your onboarding to continue")
  DATE_OF_BIRTH_IN_FUTURE = Error.new(code: "VALIDATION_FAILED", message: "cannot be in the future")
  DATE_OF_BIRTH_TOO_OLD = Error.new(code: "VALIDATION_FAILED", message: "is too far in the past. Check the year")
  PHONE_INVALID = Error.new(code: "VALIDATION_FAILED", message: "must be in international format, for example +14155552671")
  STATE_INVALID = Error.new(code: "VALIDATION_FAILED", message: "must be a two-letter US state code, for example CA")
  POSTAL_CODE_INVALID = Error.new(code: "VALIDATION_FAILED", message: "must be a US ZIP code, for example 94105 or 94105-1234")
  COUNTRY_UNSUPPORTED = Error.new(code: "VALIDATION_FAILED", message: "must be US. Only United States addresses are accepted")
  TERMS_VERSION_OUTDATED = Error.new(code: "VALIDATION_FAILED", message: "must be the current version of the terms. Reload the terms and accept again")
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
