module Types
  class QueryType < Types::BaseObject
    description "Entry point for reading data"

    field :me, resolver: Queries::Users::Me
    field :users, resolver: Queries::Users::ListUsers
    field :email_logs, resolver: Queries::EmailLogs::ListEmailLogs
    field :email_log, resolver: Queries::EmailLogs::ShowEmailLog
  end
end
