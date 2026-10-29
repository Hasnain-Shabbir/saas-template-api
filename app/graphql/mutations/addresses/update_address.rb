module Mutations
  module Addresses
    class UpdateAddress < BaseMutation
      description "Saves the US address of the logged-in user. Sending the same data again changes nothing. Saving a complete address finishes the address onboarding step."

      null true

      argument :address_line_1, String, required: true, description: "Street address, up to 100 characters"
      argument :address_line_2, String, required: false, description: "Apartment, suite or unit, up to 100 characters. Leave it out when there is none: this clears a saved value"
      argument :city, String, required: true, description: "City, up to 100 characters"
      argument :state, String, required: true, description: "Two-letter US state code, for example CA"
      argument :postal_code, String, required: true, description: "US ZIP code, for example 94105 or 94105-1234"
      argument :country, String, required: true, description: "Country code. Only US is accepted"

      field :user, Types::UserType, null: true, description: "The user with the saved address. Empty when the address could not be saved"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      def resolve(**attributes)
        authorize!(current_user, :update_address?)
        result = ::Addresses::Update.call(user: current_user, **attributes)

        { user: result.value, errors: errors_from(result) }
      end
    end
  end
end
