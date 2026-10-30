require "rails_helper"

# A list of objects costs more than a single field, so one query cannot ask for many lists at no cost (graphql-operations.md).
RSpec.describe "List complexity" do
  # Older list fields, made before `LIST_COMPLEXITY` existed: the `errors` of every payload and `Onboarding.steps`. They are short
  # lists the server builds, not rows from a table. The owner decides whether to give them the cost too; until then they are the
  # only exception, and a new list field must pass.
  def legacy?(name)
    name.end_with?("Payload.errors") || name == "Onboarding.steps"
  end

  def list_of_objects?(type)
    type = type.of_type while type.non_null?
    type.list? && type.unwrap.kind.object?
  end

  def list_fields
    types = SaasTemplateApiSchema.types.values.select { |type| type.kind.object? && !type.graphql_name.start_with?("__") }
    types.flat_map do |type|
      type.fields.values.select { |field| list_of_objects?(field.type) }.map { |field| [ "#{type.graphql_name}.#{field.graphql_name}", field ] }
    end.to_h
  end

  it "gives every new list field of objects the list complexity" do
    new_fields = list_fields.reject { |name, _| legacy?(name) }

    expect(new_fields.keys).to include("EmailLogPage.items")
    expect(new_fields.reject { |_, field| field.complexity == Types::BaseField::LIST_COMPLEXITY }.keys).to be_empty
  end
end
