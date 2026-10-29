module Types
  class OnboardingStepType < Types::BaseObject
    description "One step of the onboarding of the logged-in user"

    field :key, String, null: false, description: "Stable name of the step. The server marks it done when the user saves the data the step needs"
    field :completed, Boolean, null: false, description: "True when the user has finished this step"
    field :completed_at, GraphQL::Types::ISO8601DateTime, null: true, description: "When the step was finished. Empty until then"
  end
end
