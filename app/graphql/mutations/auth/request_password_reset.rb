module Mutations
  module Auth
    class RequestPasswordReset < BaseMutation
      description "Emails a password reset link if an account has this email. The answer is the same for every email."

      null true

      argument :email, String, required: true, description: "Email of the account"

      field :success, Boolean, null: false, description: "Always true for a well-formed email, so it never shows whether the email has an account"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      # Public operation: the user cannot log in, that is why they ask.
      def ready?(**_args)
        true
      end

      def resolve(email:)
        result = ::Auth::RequestPasswordReset.call(email:)

        { success: result.success?, errors: errors_from(result) }
      end
    end
  end
end
