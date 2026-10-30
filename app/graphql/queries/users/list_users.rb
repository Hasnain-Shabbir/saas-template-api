module Queries
  module Users
    class ListUsers < BaseQuery
      description "One page of the members list, newest first, with optional filters. A super_admin is never in the list. Only a super_admin may ask. Fails with FORBIDDEN for anyone else"

      type Types::UserPageType, null: false

      argument :role, Types::UserListRoleEnum, required: false, description: "Only users with this role"
      argument :created_from, GraphQL::Types::ISO8601Date, required: false, description: "Only users created from this day on (included)"
      argument :created_to, GraphQL::Types::ISO8601Date, required: false, description: "Only users created up to this day (included)"
      argument :search, String, required: false, description: "Part of the email, first name or last name, in any letter case"
      argument :page, Integer, required: false, description: "Page number, starting at 1. A lower number is read as 1"
      argument :per_page, Integer, required: false,
               description: "Users per page. #{ValidationRules::PAGE_SIZE_DEFAULT} when empty, at most #{ValidationRules::PAGE_SIZE_MAX}"

      def resolve(**filters)
        authorize!(User, :index?)
        ::Users::List.call(**filters).value
      end
    end
  end
end
