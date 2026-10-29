module Mutations
  module Terms
    class AcceptTerms < BaseMutation
      description "Records that the logged-in user accepted the terms and privacy policy, with the time. Accepting again changes nothing. This finishes the terms onboarding step."

      null true

      argument :version, String, required: true, description: "The version of the terms the user was shown. It must be the current one, or the call fails with VALIDATION_FAILED"

      field :user, Types::UserType, null: true, description: "The user with the recorded acceptance. Empty when it could not be recorded"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      def resolve(version:)
        authorize!(current_user, :accept_terms?)
        result = ::Terms::Accept.call(user: current_user, version:)

        { user: result.value, errors: errors_from(result) }
      end
    end
  end
end
