module Onboarding
  # What the services return and the GraphQL types show. `current_step` is the key of the first step still to do, or nil when
  # nothing is left (or the role has no steps). `completed` is true exactly then.
  Progress = Data.define(:steps, :current_step, :completed)
end
