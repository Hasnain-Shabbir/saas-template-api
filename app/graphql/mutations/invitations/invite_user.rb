module Mutations
  module Invitations
    class InviteUser < BaseMutation
      description "Emails an invitation link to an address. Only a super_admin may do this, and only for roles they may grant. An address that already has an account gets no email."

      null true

      argument :email, String, required: true, description: "The address to invite"
      argument :role, Types::InvitationRoleEnum, required: true, description: "The role the new user gets. Required, so a forgotten role never invites someone by accident"

      field :success, Boolean, null: false, description: "Always true for a well-formed email, so it never shows whether the email has an account"
      field :errors, [ Types::UserErrorType ], null: false, description: "Expected failures. Empty when the operation succeeded"

      def resolve(email:, role:)
        authorize!(Invitation.new(email:, role:), :create?)
        result = ::Invitations::Invite.call(email:, role:, inviter: current_user)

        { success: result.success?, errors: errors_from(result) }
      end
    end
  end
end
