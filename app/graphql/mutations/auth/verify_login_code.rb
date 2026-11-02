module Mutations
  module Auth
    class VerifyLoginCode < BaseMutation
      description "Checks the code from the login email and returns a token for a new session. The code works once."

      null true

      argument :email, String, required: true, description: "Email of the account"
      argument :code, String, required: true, description: "The code from the login email"

      field :token, String, description: "Token to send as `Authorization: Bearer <token>` on later requests"
      field :user, Types::UserType, description: "The user the token belongs to"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      # Public operation: the code is the proof.
      def ready?(**_args)
        true
      end

      def resolve(email:, code:)
        result = ::Auth::VerifyLogin.call(email:, code:)
        value = result.value || {}

        { token: value[:token], user: value[:user], errors: errors_from(result) }
      end
    end
  end
end
