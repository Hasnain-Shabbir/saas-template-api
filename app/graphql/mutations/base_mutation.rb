module Mutations
  class BaseMutation < GraphQL::Schema::RelayClassicMutation
    include Authenticatable
    include Authorizable
    include ResultErrors

    argument_class Types::BaseArgument
    field_class Types::BaseField
    input_object_class Types::BaseInputObject
    object_class Types::BaseObject

    # Default deny: login is required. Public operations override this (sign up, login).
    def ready?(**_args)
      current_user!
      true
    end
  end
end
