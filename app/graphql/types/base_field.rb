# frozen_string_literal: true

module Types
  class BaseField < GraphQL::Schema::Field
    argument_class Types::BaseArgument

    # `sensitive: :contact` marks a field whose read must be logged (who viewed what). The value is the field group name stored in
    # the read audit log (`ReadAudit::FIELD_GROUPS`). Reading your own record is not logged.
    def initialize(*args, sensitive: nil, **kwargs, &block)
      super(*args, **kwargs, &block)
      extension(Types::SensitiveFieldExtension, group: sensitive) if sensitive
    end
  end
end
