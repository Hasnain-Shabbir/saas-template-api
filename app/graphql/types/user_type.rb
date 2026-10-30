module Types
  class UserType < Types::BaseObject
    description "A person who can log in"

    field :id, ID, null: false, description: "Unique id of the user"
    field :email, String, null: false, description: "Email the user logs in with"
    field :role, Types::UserRoleEnum, null: false, description: "The role of the user, for example to show or hide screens. The API still checks every request"

    # Personal data. Reading date_of_birth, phone, or address as someone else is logged (`sensitive:`, see `ReadAudit`).
    # A user is only ever returned to themselves today (me, login, signUp, acceptInvitation). An operation that returns
    # another user must hide `date_of_birth` and `phone` through a policy first, with a test.
    field :first_name, String, null: true, description: "First name. Empty until the profile is saved"
    field :last_name, String, null: true, description: "Last name. Empty until the profile is saved"
    field :date_of_birth, GraphQL::Types::ISO8601Date, null: true, sensitive: :date_of_birth, description: "Date of birth. Empty until the profile is saved"
    field :phone, String, null: true, sensitive: :contact, description: "Phone number in international format. Empty until the profile is saved"

    # The address is personal data too: the same rule as above.
    field :address_line_1, String, null: true, sensitive: :address, description: "Street address. Empty until the address is saved"
    field :address_line_2, String, null: true, sensitive: :address, description: "Apartment, suite or unit. Empty when there is none"
    field :city, String, null: true, sensitive: :address, description: "City. Empty until the address is saved"
    field :state, String, null: true, sensitive: :address, description: "Two-letter US state code. Empty until the address is saved"
    field :postal_code, String, null: true, sensitive: :address, description: "US ZIP code. Empty until the address is saved"
    field :country, String, null: true, sensitive: :address, description: "Country code, always US for now. Empty until the address is saved"

    field :terms_version, String, null: true, description: "The version of the terms the user accepted. Empty until they accept"
    field :terms_accepted_at, GraphQL::Types::ISO8601DateTime, null: true, description: "When the user accepted the terms. Empty until they accept"

    field :onboarding, Types::OnboardingType, null: false, description: "The onboarding progress of this user. The server finishes a step when the data it needs is saved"

    def onboarding = ::Onboarding::Status.call(user: object).value
  end
end
