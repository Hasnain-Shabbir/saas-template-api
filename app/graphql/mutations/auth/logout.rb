module Mutations
  module Auth
    class Logout < BaseMutation
      description "Ends the current session. Its token stops working immediately."

      null true

      field :success, Boolean, null: false, description: "True when the session was ended"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      def resolve
        authorize!(current_user, :logout?)
        result = ::Auth::Logout.call(user: current_user, token: context[:token])

        { success: result.success?, errors: errors_from(result) }
      end
    end
  end
end
