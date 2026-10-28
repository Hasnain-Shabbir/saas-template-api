# frozen_string_literal: true

class SaasTemplateApiSchema < GraphQL::Schema
  mutation(Types::MutationType)
  query(Types::QueryType)

  # For batch-loading (see https://graphql-ruby.org/dataloader/overview.html)
  use GraphQL::Dataloader

  # An unknown error never reaches the client. The class and backtrace go to the log
  # (not the message, which can hold personal data) and the full error to the error reporter.
  # Only in development and test the message is logged too, so errors can be debugged locally.
  rescue_from(StandardError) do |error, _object, _args, _context, field|
    detail = Rails.env.local? ? "#{error.class}: #{error.message}" : error.class
    Rails.logger.error("GraphQL error in #{field&.path}: #{detail}\n#{error.backtrace&.first(10)&.join("\n")}")
    Rails.error.report(error, handled: true, source: "graphql")
    raise Errors.execution_error(Errors::INTERNAL_ERROR)
  end

  # GraphQL-Ruby calls this when something goes wrong while running a query:
  def self.type_error(err, context)
    # if err.is_a?(GraphQL::InvalidNullError)
    #   # report to your bug tracker here
    #   return nil
    # end
    super
  end

  # Limit the depth and size of incoming queries:
  max_depth(15)
  max_query_string_tokens(5000)

  # Stop validating when it encounters this many errors:
  validate_max_errors(100)
end
