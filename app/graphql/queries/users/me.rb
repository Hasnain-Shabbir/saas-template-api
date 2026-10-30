module Queries
  module Users
    class Me < BaseQuery
      description "The logged-in user. Fails with UNAUTHENTICATED when nobody is logged in"

      type Types::UserType, null: true

      def resolve
        authorize!(current_user!, :show?)
      end
    end
  end
end
