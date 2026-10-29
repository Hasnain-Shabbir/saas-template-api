module Onboarding
  # One onboarding step. `roles` (nil = every role) says who has it. `complete_when` is checked by the server before the step
  # may be completed, so a client cannot mark a step done without doing its work. `operations` are the GraphQL operations the user
  # needs while the step is open (for example the one that saves the profile): the onboarding gate lets them through.
  Step = Data.define(:key, :roles, :complete_when, :operations) do
    def initialize(key:, roles: nil, complete_when: ->(_user) { true }, operations: [])
      super(key: key.to_s.freeze, roles: roles&.map(&:to_s)&.freeze, complete_when:, operations: operations.map(&:to_s).freeze)
    end

    def applies_to?(user) = roles.nil? || roles.include?(user.role)

    def satisfied_by?(user) = complete_when.call(user) == true
  end
end
