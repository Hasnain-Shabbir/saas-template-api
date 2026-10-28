module Types
  class UserErrorType < Types::BaseObject
    description "An expected failure, safe to show to the end user"

    field :message, String, null: false, description: "Short message for the end user"
    field :path, [ String ], null: false, description: "Where the problem is, for example input, email"
    field :code, String, null: false, description: "Stable error code, for example VALIDATION_FAILED"
  end
end
