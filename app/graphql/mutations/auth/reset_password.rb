module Mutations
  module Auth
    class ResetPassword < BaseMutation
      description "Sets a new password with the code from the reset email. The code works once, every session of the user ends, and a locked account is unlocked."

      null true

      argument :email, String, required: true, description: "Email of the account"
      argument :code, String, required: true, description: "The code from the reset email"
      argument :password, String, required: true, description: "The new password"

      field :success, Boolean, null: false, description: "True when the password was changed"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      # Public operation: the code is the proof.
      def ready?(**_args)
        true
      end

      def resolve(email:, code:, password:)
        result = ::Auth::ResetPassword.call(email:, code:, password:)

        { success: result.success?, errors: errors_from(result) }
      end
    end
  end
end
