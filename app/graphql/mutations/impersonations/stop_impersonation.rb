module Mutations
  module Impersonations
    class StopImpersonation < BaseMutation
      description "Ends the impersonation session of the token that sends it. That token stops working at once. The admin's own token is not touched. Send it with the impersonation token"

      null true

      field :success, Boolean, null: false, description: "True when the session was ended"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      def resolve
        authorize!(current_user, :stop_impersonation?)
        result = impersonating? ? ::Impersonations::Stop.call(impersonation:) : Errors.failure(Errors::NOT_IMPERSONATING)

        { success: result.success?, errors: errors_from(result) }
      end
    end
  end
end
