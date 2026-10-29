module Types
  class OnboardingType < Types::BaseObject
    description "How far the logged-in user is with onboarding. Until it is complete, the API refuses every other operation with ONBOARDING_REQUIRED"

    field :completed, Boolean, null: false, description: "True when no step is left. Also true for a role that has no steps"
    field :current_step, String, null: true, description: "Key of the next step to do. Empty when onboarding is complete"
    field :steps, [ Types::OnboardingStepType ], null: false, description: "The steps of the user's role, in the order they must be done"
  end
end
