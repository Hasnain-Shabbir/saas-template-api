module Mutations
  module Auth
    class SignUp < BaseMutation
      description "Creates a user account and returns a token for a new session. Turned off unless the server allows public sign up, then it is FORBIDDEN."

      null true

      argument :email, String, required: true, description: "Email for the new account"
      argument :password, String, required: true, description: "Password for the new account"

      field :token, String, description: "Token to send as `Authorization: Bearer <token>` on later requests"
      field :user, Types::UserType, description: "The user the token belongs to"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      # Public operation: nobody is logged in yet. Off by default (invite only), then FORBIDDEN.
      def ready?(**_args)
        raise Errors.execution_error(Errors::SIGN_UP_DISABLED) unless Rails.configuration.x.allow_public_sign_up

        true
      end

      def resolve(email:, password:)
        result = ::Auth::SignUp.call(email:, password:)
        value = result.value || {}

        { token: value[:token], user: value[:user], errors: errors_from(result) }
      end
    end
  end
end
