module Mutations
  class BaseMutation < GraphQL::Schema::RelayClassicMutation
    include Authenticatable

    argument_class Types::BaseArgument
    field_class Types::BaseField
    input_object_class Types::BaseInputObject
    object_class Types::BaseObject

    # Default deny: login is required. Public operations override this (sign up, login).
    def ready?(**_args)
      current_user!
      true
    end

    private

    # Turns a failed Result into the payload's `errors` list.
    def errors_from(result)
      return [] if result.success?
      return [ { message: result.message, path: [ "input" ], code: result.code } ] unless result.errors

      result.errors.map do |error|
        { message: error.full_message, path: [ "input", error.attribute.to_s.camelize(:lower) ], code: result.code }
      end
    end
  end
end
