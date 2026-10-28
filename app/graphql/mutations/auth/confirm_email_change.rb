module Mutations
  module Auth
    class ConfirmEmailChange < BaseMutation
      description "Finishes an email change with the code from the email sent to the new address. The code works once. Every other session of the user ends."

      null true

      argument :code, String, required: true, description: "The code from the email sent to the new address"

      field :success, Boolean, null: false, description: "True when the email was changed"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      def resolve(code:)
        authorize!(current_user, :change_email?)
        result = ::Auth::ConfirmEmailChange.call(user: current_user, code:, token: context[:token])

        { success: result.success?, errors: errors_from(result) }
      end
    end
  end
end
