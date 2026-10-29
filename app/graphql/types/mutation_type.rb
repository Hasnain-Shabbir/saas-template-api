module Types
  class MutationType < Types::BaseObject
    description "Entry point for changing data"

    field :sign_up, mutation: Mutations::Auth::SignUp
    field :login, mutation: Mutations::Auth::Login
    field :logout, mutation: Mutations::Auth::Logout
    field :request_password_reset, mutation: Mutations::Auth::RequestPasswordReset
    field :reset_password, mutation: Mutations::Auth::ResetPassword
    field :request_email_change, mutation: Mutations::Auth::RequestEmailChange
    field :confirm_email_change, mutation: Mutations::Auth::ConfirmEmailChange
    field :invite_user, mutation: Mutations::Invitations::InviteUser
    field :accept_invitation, mutation: Mutations::Invitations::AcceptInvitation
    field :revoke_invitation, mutation: Mutations::Invitations::RevokeInvitation
    field :resend_invitation, mutation: Mutations::Invitations::ResendInvitation
  end
end
