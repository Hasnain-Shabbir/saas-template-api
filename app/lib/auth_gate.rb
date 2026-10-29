# Decides, from the query text alone, whether a request needs a login. The controller asks it before GraphQL runs, so a request
# that needs a login and has none is UNAUTHENTICATED and nothing else: GraphQL's own checks (a missing argument, an unknown enum
# value, a bad variable) would otherwise answer first and tell an anonymous caller about the shape of a protected operation.
# Order of checks: authentication (401), authorization (403), input validation (422).
module AuthGate
  # A request needs a login when any root field it runs is not a public operation. Introspection (`__schema`, `__typename`) is
  # not data (it is switched off in production by the schema).
  # A query that cannot be parsed, or names no single operation, returns false: GraphQL rejects it as BAD_REQUEST, with no data.
  def self.login_required?(query, operation_name: nil)
    document = GraphQL.parse(query, max_tokens: SaasTemplateApiSchema.max_query_string_tokens)
    operation = pick_operation(document, operation_name)
    return false unless operation

    fragments = document.definitions.grep(GraphQL::Language::Nodes::FragmentDefinition).index_by(&:name)
    root_fields(operation.selections, fragments, Set.new).any? { |name| !public?(name) }
  rescue GraphQL::ParseError
    false
  end

  def self.public?(field_name)
    field_name.start_with?("__") || Rack::Attack::PUBLIC_OPERATIONS.include?(field_name)
  end
  private_class_method :public?

  def self.pick_operation(document, operation_name)
    operations = document.definitions.grep(GraphQL::Language::Nodes::OperationDefinition)
    return operations.first if operation_name.nil? && operations.one?

    operations.find { |operation| operation.name == operation_name } if operation_name
  end
  private_class_method :pick_operation

  # Field names at the root, through inline fragments and named fragments (aliases cannot hide one: `name` is the real field).
  def self.root_fields(selections, fragments, seen)
    selections.flat_map do |selection|
      case selection
      when GraphQL::Language::Nodes::Field then [ selection.name ]
      when GraphQL::Language::Nodes::InlineFragment then root_fields(selection.selections, fragments, seen)
      when GraphQL::Language::Nodes::FragmentSpread
        fragment = fragments[selection.name]
        fragment && seen.add?(selection.name) ? root_fields(fragment.selections, fragments, seen) : []
      else []
      end
    end
  end
  private_class_method :root_fields
end
