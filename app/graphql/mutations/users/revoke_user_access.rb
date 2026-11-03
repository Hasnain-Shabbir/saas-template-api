module Mutations
  module Users
    class RevokeUserAccess < BaseMutation
      description "Takes the access of a user away: they can no longer log in, and their tokens and pending codes stop working at once. Their data is kept and they stay in the list. Only a super_admin may do this, and never to a super_admin"

      null true

      argument :id, ID, required: true, description: "Id of the user whose access is revoked"

      field :user, Types::UserSummaryType, null: true, description: "The user whose access was revoked. Empty when the operation failed"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      def resolve(id:)
        # Only a super_admin may look users up, so anyone else gets FORBIDDEN whether the id exists or not.
        authorize!(User, :index?)
        target = User.find_by(id:) || raise(Errors.execution_error(Errors::NOT_FOUND))
        authorize!(target, :revoke_access?)
        result = ::Users::RevokeAccess.call(user: target)

        { user: result.value, errors: errors_from(result) }
      end
    end
  end
end
