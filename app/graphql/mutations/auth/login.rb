module Mutations
  module Auth
    class Login < BaseMutation
      description "Checks the email and password and emails a login code. Send the code to `verifyLoginCode` to get a token."

      null true

      argument :email, String, required: true, description: "Email of the account"
      argument :password, String, required: true, description: "Password of the account"

      field :success, Boolean, null: false, description: "True when the password was right and a login code was sent to the email of the account"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      # Public operation: nobody is logged in yet.
      def ready?(**_args)
        true
      end

      def resolve(email:, password:)
        result = ::Auth::Login.call(email:, password:)

        { success: result.success?, errors: errors_from(result) }
      end
    end
  end
end
