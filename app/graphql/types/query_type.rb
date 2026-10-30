module Types
  class QueryType < Types::BaseObject
    description "Entry point for reading data"

    include Authorizable

    field :me, Types::UserType, description: "The logged-in user. Fails with UNAUTHENTICATED when nobody is logged in"

    field :email_logs, Types::EmailLogPageType, null: false,
          description: "One page of the email log, newest first, with optional filters. Only a super_admin may ask. Fails with FORBIDDEN for anyone else" do
      argument :from, GraphQL::Types::ISO8601Date, required: false, description: "Only entries from this day on (included)"
      argument :to, GraphQL::Types::ISO8601Date, required: false, description: "Only entries up to this day (included)"
      argument :status, Types::EmailLogStatusEnum, required: false, description: "Only entries with this status"
      argument :search, String, required: false, description: "Part of the recipient address, in any letter case"
      argument :page, Integer, required: false, description: "Page number, starting at 1. A lower number is read as 1"
      argument :per_page, Integer, required: false,
               description: "Entries per page. #{ValidationRules::PAGE_SIZE_DEFAULT} when empty, at most #{ValidationRules::PAGE_SIZE_MAX}"
    end

    field :email_log, Types::EmailLogType, null: true,
          description: "One entry of the email log. Only a super_admin may ask. Fails with NOT_FOUND when there is no such entry" do
      argument :id, ID, required: true, description: "Id of the log entry"
    end

    def me
      authorize!(current_user!, :show?)
    end

    def email_logs(**filters)
      authorize!(EmailLog, :index?)
      EmailLogs::List.call(**filters).value
    end

    def email_log(id:)
      authorize!(EmailLog, :show?)
      EmailLog.find_by(id:) || raise(Errors.execution_error(Errors::NOT_FOUND))
    end
  end
end
