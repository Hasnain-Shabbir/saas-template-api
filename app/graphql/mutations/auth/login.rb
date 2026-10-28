module Mutations
  module Auth
    class Login < BaseMutation
      description "Checks the email and password and returns a token for a new session."

      null true

      argument :email, String, required: true, description: "Email of the account"
      argument :password, String, required: true, description: "Password of the account"

      field :token, String, description: "Token to send as `Authorization: Bearer <token>` on later requests"
      field :user, Types::UserType, description: "The user the token belongs to"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      # Public operation: nobody is logged in yet.
      def ready?(**_args)
        true
      end

      def resolve(email:, password:)
        result = ::Auth::Login.call(email:, password:)
        value = result.value || {}

        { token: value[:token], user: value[:user], errors: errors_from(result) }
      end
    end
  end
end
