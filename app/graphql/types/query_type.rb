module Types
  class QueryType < Types::BaseObject
    description "Entry point for reading data"

    include Authenticatable

    field :me, Types::UserType, description: "The logged-in user. Fails with UNAUTHENTICATED when nobody is logged in"

    def me
      current_user!
    end
  end
end
