module Onboarding
  # The one place onboarding steps are defined. The order of the list is the order the user must follow.
  # A project adds a step by adding a line here, and nowhere else (no migration, no schema change). Example:
  #   Step.new(key: "profile", complete_when: ->(user) { user.profile_complete? }, operations: %w[updateProfile])
  # A spec checks every step in this list. While a step is open, the user can reach only the operations that finish it (see `OnboardingGate`).
  module Registry
    STEPS = [
      # super_admin has no profile step: the first super_admin is made by the seeds, not by a person filling in a form.
      Step.new(key: "profile", roles: %w[member], complete_when: ->(user) { user.profile_complete? }, operations: %w[updateProfile]),
      Step.new(key: "address", roles: %w[member], complete_when: ->(user) { user.address_complete? }, operations: %w[updateAddress]),
      Step.new(key: "terms", roles: %w[member], complete_when: ->(user) { user.terms_accepted? }, operations: %w[acceptTerms])
    ].freeze

    # The steps one user has, in order. A step of another role is invisible: it is not listed and not accepted.
    def self.steps_for(user)
      STEPS.select { |step| step.applies_to?(user) }
    end
  end
end
