require "rails_helper"

RSpec.describe "Schema descriptions" do
  let(:types) { SaasTemplateApiSchema.types.values.reject { |type| type.graphql_name.start_with?("__") } }
  let(:custom_types) { types.reject { |type| type.kind.scalar? && type.default_scalar? } }

  def missing(items)
    items.select { |item| item.description.blank? }
  end

  it "describes every type" do
    expect(missing(custom_types).map(&:graphql_name)).to be_empty
  end

  it "describes every field and argument" do
    fields = custom_types.select { |type| type.kind.fields? }.flat_map { |type| type.fields.values.map { |field| [ type, field ] } }
    arguments = fields.flat_map { |type, field| field.arguments.values.map { |argument| [ type, field, argument ] } }
    inputs = custom_types.select { |type| type.kind.input_object? }.flat_map { |type| type.arguments.values.map { |argument| [ type, nil, argument ] } }

    names = fields.select { |_, field| field.description.blank? }.map { |type, field| "#{type.graphql_name}.#{field.graphql_name}" }
    names += (arguments + inputs).select { |*, argument| argument.description.blank? }
                                 .map { |type, field, argument| [ type.graphql_name, field&.graphql_name, argument.graphql_name ].compact.join(".") }

    expect(names).to be_empty
  end
end
