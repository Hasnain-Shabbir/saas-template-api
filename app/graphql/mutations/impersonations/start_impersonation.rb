module Mutations
  module Impersonations
    class StartImpersonation < BaseMutation
      description "Starts a session in which the admin acts as a member, and returns a token for it that lasts 30 minutes. Their own token keeps working. A session they already had open is ended and its token stops working. Only a super_admin may do this, never to a super_admin and never to an archived or access-revoked user. The session and everything done in it are recorded"

      null true

      argument :user_id, ID, required: true, description: "Id of the member to act as"
      argument :reason_category, Types::ImpersonationReasonCategoryEnum, required: true, description: "Why the session is started"
      argument :reason, String, required: false, description: "A short note. Required when the category is OTHER. Never put personal or health data in it"

      field :token, String, description: "Token to send as `Authorization: Bearer <token>` to act as the member. Keep the admin's own token to go back"
      field :impersonation, Types::ImpersonationType, description: "The session that was started. Empty when the operation failed"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      def resolve(user_id:, reason_category:, reason: nil)
        # Only a super_admin may look users up, so anyone else gets FORBIDDEN whether the id exists or not.
        authorize!(User, :index?)
        target = User.find_by(id: user_id) || raise(Errors.execution_error(Errors::NOT_FOUND))
        authorize!(target, :impersonate?)
        result = ::Impersonations::Start.call(impersonator: current_user, target:, reason_category:, reason:, request_id: context[:request_id])
        started = result.value

        { token: started&.token, impersonation: started&.impersonation, errors: errors_from(result) }
      end
    end
  end
end
