module Mutations
  module Invitations
    class AcceptInvitation < BaseMutation
      description "Creates the invited account with the token from the invitation email and returns a token for a new session. The invitation works once."

      null true

      argument :invitation_token, String, required: true, description: "The token from the invitation link"
      argument :password, String, required: true, description: "The password for the new account"

      field :token, String, description: "Token to send as `Authorization: Bearer <token>` on later requests"
      field :user, Types::UserType, description: "The user that was created"
      field :onboarding, Types::OnboardingType, description: "The onboarding steps of the new user. `currentStep` is the step to open first. Same data as `me { onboarding }`"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      # Public operation: the invitation token is the proof.
      def ready?(**_args)
        true
      end

      def resolve(invitation_token:, password:)
        result = ::Invitations::Accept.call(token: invitation_token, password:)
        value = result.value || {}

        { token: value[:token], user: value[:user], onboarding: value[:onboarding], errors: errors_from(result) }
      end
    end
  end
end
