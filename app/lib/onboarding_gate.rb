# Decides, from the query text alone, whether a logged-in user must finish onboarding before the request runs. Like `AuthGate`, the
# controller asks it before GraphQL runs, for queries and mutations alike: default deny, so a new operation is blocked until its
# step is done, with no change to the operation. Order of checks: authentication (401), onboarding, authorization (403), input (422).
module OnboardingGate
  # Always open to a logged-in user: read who I am (with my onboarding), log out. Public operations stay open too.
  # The operations a step needs (the one that saves its data) are listed on the step in `Onboarding::Registry`, not here.
  ALWAYS_OPEN = %w[me logout].freeze

  # True when the user has unfinished steps and the request runs any root field that is not open.
  # A role with no steps is never blocked, and costs no query.
  def self.blocked?(user, query, operation_name: nil)
    steps = Onboarding::Registry.steps_for(user)
    return false if steps.empty?

    open = ALWAYS_OPEN + Rack::Attack::PUBLIC_OPERATIONS + steps.flat_map(&:operations)
    names = AuthGate.root_field_names(query, operation_name:)
    return false if names.all? { |name| name.start_with?("__") || open.include?(name) }

    !Onboarding::Status.call(user:).value.completed
  end
end
