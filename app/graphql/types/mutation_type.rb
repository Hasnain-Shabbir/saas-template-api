module Types
  class MutationType < Types::BaseObject
    description "Entry point for changing data"

    field :sign_up, mutation: Mutations::Auth::SignUp
    field :login, mutation: Mutations::Auth::Login
    field :logout, mutation: Mutations::Auth::Logout
  end
end
