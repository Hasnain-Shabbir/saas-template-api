module Onboarding
  # One step of the list a user sees. Only these three facts leave the API: never the roles or the check of a step.
  StepStatus = Data.define(:key, :completed, :completed_at)
end
