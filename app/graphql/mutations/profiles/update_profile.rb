module Mutations
  module Profiles
    class UpdateProfile < BaseMutation
      description "Saves the name, date of birth and phone number of the logged-in user. Sending the same data again changes nothing. Date of birth and phone are stored encrypted."

      null true

      argument :first_name, String, required: true, description: "First name, up to 100 characters"
      argument :last_name, String, required: true, description: "Last name, up to 100 characters"
      argument :date_of_birth, GraphQL::Types::ISO8601Date, required: true, description: "Date of birth, for example 1990-05-21. Not in the future"
      argument :phone, String, required: true, description: "Phone number in international format, for example +14155552671. Spaces and dashes are ignored"

      field :user, Types::UserType, null: true, description: "The user with the saved profile. Empty when the profile could not be saved"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      def resolve(**attributes)
        authorize!(current_user, :update_profile?)
        result = ::Profiles::Update.call(user: current_user, **attributes)

        { user: result.value, errors: errors_from(result) }
      end
    end
  end
end
