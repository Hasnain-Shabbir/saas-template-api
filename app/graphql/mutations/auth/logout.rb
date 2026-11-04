module Mutations
  module Auth
    class Logout < BaseMutation
      description "Ends the current session. Its token stops working immediately. With an impersonation token it ends only the impersonation, never the admin's own session."

      null true

      field :success, Boolean, null: false, description: "True when the session was ended"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      def resolve
        authorize!(current_user, :logout?)
        # An impersonation token is ended through its session, so the log says it ended. The admin's own login is never touched.
        result = impersonating? ? ::Impersonations::Stop.call(impersonation:) : ::Auth::Logout.call(user: current_user, token: context[:token])

        { success: result.success?, errors: errors_from(result) }
      end
    end
  end
end
