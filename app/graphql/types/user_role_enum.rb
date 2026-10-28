module Types
  # Built from User.roles, so a new role is added in one place (the enum on User).
  class UserRoleEnum < GraphQL::Schema::Enum
    graphql_name "UserRole"
    description "What a user is, which decides what they may do"

    User.roles.each_key do |role|
      value role.upcase, value: role, description: "The #{role.humanize(capitalize: false)} role"
    end
  end
end
