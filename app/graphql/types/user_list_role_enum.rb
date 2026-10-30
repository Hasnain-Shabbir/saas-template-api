module Types
  # The roles the admin users list can be filtered by. Only members are listed for now (a super_admin is never in the list),
  # so this is narrower than `UserRoleEnum`, which must still be able to say SUPER_ADMIN for `me`. Add a role here when the list shows it.
  class UserListRoleEnum < GraphQL::Schema::Enum
    graphql_name "UserListRole"
    description "A role the users list can be filtered by"

    value "MEMBER", value: "member", description: "The member role"
  end
end
