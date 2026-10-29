module Mutations
  module Invitations
    class RevokeInvitation < BaseMutation
      description "Cancels the open invitation for an address. Its link stops working at once. Only a super_admin may do this."

      null true

      argument :email, String, required: true, description: "The address that was invited"

      field :success, Boolean, null: false, description: "Always true for a well-formed email, so it never shows which addresses were invited"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      def resolve(email:)
        authorize!(Invitation, :revoke?)
        result = ::Invitations::Revoke.call(email:)

        { success: result.success?, errors: errors_from(result) }
      end
    end
  end
end
