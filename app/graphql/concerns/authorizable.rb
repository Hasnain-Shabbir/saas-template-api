# Asks a Pundit policy before an operation runs. Default deny: a missing policy, a missing
# policy method, or anything other than a literal `true` is FORBIDDEN.
module Authorizable
  include Authenticatable

  # Returns the record when allowed. Nobody logged in is UNAUTHENTICATED, not FORBIDDEN.
  def authorize!(record, query)
    current_user!
    raise Errors.execution_error(Errors::FORBIDDEN) unless allowed?(record, query)

    record
  end

  private

  def allowed?(record, query)
    policy = Pundit.policy!(current_user, record)
    policy.respond_to?(query) && policy.public_send(query) == true
  rescue Pundit::NotDefinedError
    false
  end
end
