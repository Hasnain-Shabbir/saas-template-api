module Queries
  module Invitations
    class InvitationStatus < BaseQuery
      include ResultErrors

      description "Checks the token from an invitation link. Public: the token is the proof. Says only whether it is valid, never who it is for. Every bad token gives INVALID_INVITATION"

      type Types::InvitationStatusType, null: false

      argument :token, String, required: true, description: "The token from the invitation link"

      def resolve(token:)
        result = ::Invitations::Check.call(token:)

        { valid: result.success?, errors: errors_from(result) }
      end
    end
  end
end
