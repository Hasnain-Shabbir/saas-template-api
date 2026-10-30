module Types
  # Built from EmailLog.statuses, so a new status is added in one place (the enum on EmailLog).
  class EmailLogStatusEnum < GraphQL::Schema::Enum
    graphql_name "EmailLogStatus"
    description "Whether the mail was handed to the mail server"

    EmailLog.statuses.each_key do |status|
      value status.upcase, value: status, description: "The mail was #{status}"
    end
  end
end
