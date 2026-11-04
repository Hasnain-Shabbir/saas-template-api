# Decides, from the query text alone, whether a request made while impersonating must be refused. Like `AuthGate` and
# `OnboardingGate`, the controller asks it before GraphQL runs: default deny, so a new mutation is blocked for an impersonator until
# it is added here on purpose. Reading (queries) is never blocked: the admin sees what the member sees, and sensitive reads go to the
# read audit log under the admin's name.
# Order of checks: authentication (401), impersonation (403), onboarding, authorization (403), input (422).
module ImpersonationGate
  # The only mutations an impersonator may run (owner decision): save the member's profile and address (support work), and end the
  # session. `logout` ends only the impersonation, never the admin's own login.
  # Everything else is refused, among them: password reset and email change (they would hand the account over), accept terms and
  # accept invitation (the member's own legal consent and identity), every public operation, and `startImpersonation`
  # (no session inside a session).
  ALLOWED_MUTATIONS = %w[updateProfile updateAddress stopImpersonation logout].freeze

  # True when the operation is a mutation that is not on the list. A query that cannot be parsed is left to GraphQL (BAD_REQUEST).
  def self.blocked?(query, operation_name: nil)
    type, names = AuthGate.root_operation(query, operation_name:)
    return false unless type == "mutation"

    names.any? { |name| !name.start_with?("__") && !ALLOWED_MUTATIONS.include?(name) }
  end
end
