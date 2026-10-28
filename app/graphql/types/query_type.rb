module Types
  class QueryType < Types::BaseObject
    description "Entry point for reading data"

    include Authorizable

    field :me, Types::UserType, description: "The logged-in user. Fails with UNAUTHENTICATED when nobody is logged in"

    def me
      authorize!(current_user!, :show?)
    end
  end
end
