module Types
  # Logs a read of a sensitive field (see `sensitive:` on `BaseField`) before the field is resolved. Once per record and group in a
  # request, however many times the query asks for it. If the log cannot be written, the field is not resolved (the error is raised).
  class SensitiveFieldExtension < GraphQL::Schema::FieldExtension
    def resolve(object:, arguments:, context:)
      seen = (context[:read_audit_seen] ||= Set.new)
      record = object.object
      group = options[:group]

      if seen.add?([ record.class.name, record.id, group ])
        reader = context[:current_user]&.id || Audit.fallback_actor
        Audit::RecordRead.call(reader:, record:, group:, request_id: context[:request_id])
      end

      yield(object, arguments)
    end
  end
end
