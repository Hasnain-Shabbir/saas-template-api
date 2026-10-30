module Queries
  module EmailLogs
    class ShowEmailLog < BaseQuery
      description "One entry of the email log. Only a super_admin may ask. Fails with NOT_FOUND when there is no such entry"

      type Types::EmailLogType, null: true

      argument :id, ID, required: true, description: "Id of the log entry"

      def resolve(id:)
        authorize!(EmailLog, :show?)
        EmailLog.find_by(id:) || raise(Errors.execution_error(Errors::NOT_FOUND))
      end
    end
  end
end
