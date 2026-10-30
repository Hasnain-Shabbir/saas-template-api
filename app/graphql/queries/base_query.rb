module Queries
  class BaseQuery < GraphQL::Schema::Resolver
    include Authorizable

    argument_class Types::BaseArgument
  end
end
