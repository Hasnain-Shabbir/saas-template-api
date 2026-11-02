module Types
  class InvitationStatusType < Types::BaseObject
    description "Whether an invitation link can still be used"

    field :valid, Boolean, null: false, description: "True when the link can be used to create an account"
    field :errors, [ Types::UserErrorType ], null: false, complexity: Types::BaseField::LIST_COMPLEXITY, description: "Expected failures. Empty when the link is valid"
  end
end
