module Mutations
  module Invitations
    class ResendInvitation < BaseMutation
      description "Emails a fresh link for the open invitation of an address. A revoked invitation is reopened first. The earlier link stops working. Only a super_admin may do this."

      null true

      argument :email, String, required: true, description: "The address that was invited"

      field :success, Boolean, null: false, description: "Always true for a well-formed email, so it never shows which addresses were invited"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      def resolve(email:)
        authorize!(Invitation, :resend?)
        result = ::Invitations::Resend.call(email:)

        { success: result.success?, errors: errors_from(result) }
      end
    end
  end
end
