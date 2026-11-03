module Mutations
  module Users
    class UnarchiveUser < BaseMutation
      description "Lets an archived member log in again, with the same password and role. Their old tokens stay revoked. Only a super_admin may do this"

      null true

      argument :id, ID, required: true, description: "Id of the member to restore"

      field :user, Types::UserSummaryType, null: true, description: "The restored member. Empty when the operation failed"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      def resolve(id:)
        authorize!(User, :index?)
        target = User.find_by(id:) || raise(Errors.execution_error(Errors::NOT_FOUND))
        authorize!(target, :unarchive?)
        result = ::Users::Unarchive.call(user: target)

        { user: result.value, errors: errors_from(result) }
      end
    end
  end
end
