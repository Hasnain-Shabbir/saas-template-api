module Mutations
  module Auth
    class RequestEmailChange < BaseMutation
      description "Starts an email change: emails a code to the new address. The login email stays the same until the code is confirmed."

      null true

      argument :new_email, String, required: true, description: "The email address the user wants to switch to"
      argument :password, String, required: true, description: "The current password of the user"

      field :success, Boolean, null: false, description: "Always true for a well-formed email and the right password, so it never shows whether the email has an account"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      def resolve(new_email:, password:)
        authorize!(current_user, :change_email?)
        result = ::Auth::RequestEmailChange.call(user: current_user, new_email:, password:)

        { success: result.success?, errors: errors_from(result) }
      end
    end
  end
end
