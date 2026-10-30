module Queries
  module EmailLogs
    class ListEmailLogs < BaseQuery
      description "One page of the email log, newest first, with optional filters. Only a super_admin may ask. Fails with FORBIDDEN for anyone else"

      type Types::EmailLogPageType, null: false

      argument :from, GraphQL::Types::ISO8601Date, required: false, description: "Only entries from this day on (included)"
      argument :to, GraphQL::Types::ISO8601Date, required: false, description: "Only entries up to this day (included)"
      argument :status, Types::EmailLogStatusEnum, required: false, description: "Only entries with this status"
      argument :search, String, required: false, description: "Part of the recipient address, in any letter case"
      argument :page, Integer, required: false, description: "Page number, starting at 1. A lower number is read as 1"
      argument :per_page, Integer, required: false,
               description: "Entries per page. #{ValidationRules::PAGE_SIZE_DEFAULT} when empty, at most #{ValidationRules::PAGE_SIZE_MAX}"

      def resolve(**filters)
        authorize!(EmailLog, :index?)
        ::EmailLogs::List.call(**filters).value
      end
    end
  end
end
