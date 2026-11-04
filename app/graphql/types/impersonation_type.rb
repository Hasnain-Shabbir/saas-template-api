module Types
  # One impersonation session, as its starter sees it. It holds no personal data (the member is shown as in the admin list).
  class ImpersonationType < Types::BaseObject
    description "A session in which a super_admin acts as a member. It ends when it is stopped or when its time runs out"

    field :id, ID, null: false, description: "Unique id of the session"
    field :target, Types::UserSummaryType, null: false, description: "The member the admin is acting as"
    field :reason_category, Types::ImpersonationReasonCategoryEnum, null: false, description: "Why the session was started"
    field :reason, String, null: true, description: "The note given when the session was started. Empty when none was needed"
    field :started_at, GraphQL::Types::ISO8601DateTime, null: false, description: "When the session started"
    field :expires_at, GraphQL::Types::ISO8601DateTime, null: false, description: "When the token of the session stops working. It cannot be extended"
  end
end
