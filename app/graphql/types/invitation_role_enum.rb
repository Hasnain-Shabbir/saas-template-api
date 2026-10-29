module Types
  # The roles an invitation may give. Built from the policy, so the list shown to clients and the rule that is enforced cannot differ.
  class InvitationRoleEnum < GraphQL::Schema::Enum
    graphql_name "InvitationRole"
    description "The role an invited user gets. Only roles that an invitation may grant are listed"

    InvitationPolicy::GRANTABLE_ROLES.each do |role|
      value role.upcase, value: role, description: "The #{role.humanize(capitalize: false)} role"
    end
  end
end
