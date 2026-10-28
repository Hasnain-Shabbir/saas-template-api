module Types
  class UserType < Types::BaseObject
    description "A person who can log in"

    field :id, ID, null: false, description: "Unique id of the user"
    field :email, String, null: false, description: "Email the user logs in with"
    field :role, Types::UserRoleEnum, null: false, description: "The role of the user, for example to show or hide screens. The API still checks every request"
  end
end
