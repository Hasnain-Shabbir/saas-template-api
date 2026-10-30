module Types
  # One row of the users list. It holds no personal data on purpose (no date of birth, phone, or address), so reading the list
  # needs no read audit row. A field of a sensitive group is added here only together with its `sensitive:` marker and a test.
  class UserSummaryType < Types::BaseObject
    description "A member as shown in the admin list: who they are, their role, and their state. Only a super_admin can read it"

    field :id, ID, null: false, description: "Unique id of the user"
    field :email, String, null: false, description: "Email the user logs in with"
    field :first_name, String, null: true, description: "First name. Empty until the profile is saved"
    field :last_name, String, null: true, description: "Last name. Empty until the profile is saved"
    field :role, Types::UserRoleEnum, null: false, description: "The role of the user"
    field :locked, Boolean, null: false, description: "True when the account is locked after too many wrong passwords"
    field :onboarding_completed, Boolean, null: false, description: "True when the user has no onboarding step left. Also true for a role that has no steps"
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false, description: "When the user was created"

    def locked = object.access_locked?

    # The same rule as `Onboarding::Status`, read from the steps already loaded for the page.
    def onboarding_completed
      done = object.onboarding_steps.map(&:step_key)
      Onboarding::Registry.steps_for(object).all? { |step| done.include?(step.key) }
    end
  end
end
