module Types
  class UserType < Types::BaseObject
    description "A person who can log in"

    field :id, ID, null: false, description: "Unique id of the user"
    field :email, String, null: false, description: "Email the user logs in with"
  end
end
