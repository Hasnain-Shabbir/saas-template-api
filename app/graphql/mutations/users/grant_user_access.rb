module Mutations
  module Users
    class GrantUserAccess < BaseMutation
      description "Gives the access back to a user whose access was revoked, with the same password and role. Their old tokens stay revoked. An archived user stays archived. Only a super_admin may do this"

      null true

      argument :id, ID, required: true, description: "Id of the user whose access is granted again"

      field :user, Types::UserSummaryType, null: true, description: "The user whose access was granted. Empty when the operation failed"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      def resolve(id:)
        authorize!(User, :index?)
        target = User.find_by(id:) || raise(Errors.execution_error(Errors::NOT_FOUND))
        authorize!(target, :grant_access?)
        result = ::Users::GrantAccess.call(user: target)

        { user: result.value, errors: errors_from(result) }
      end
    end
  end
end
