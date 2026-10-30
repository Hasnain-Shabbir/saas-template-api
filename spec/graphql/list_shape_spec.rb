require "rails_helper"

# One shape for every list of table rows (graphql-operations.md, "Lists: one shape everywhere").
RSpec.describe "List shape" do
  let(:object_types) { SaasTemplateApiSchema.types.values.select { |type| type.kind.object? && !type.graphql_name.start_with?("__") } }
  let(:page_types) { object_types.select { |type| type.graphql_name.end_with?("Page") } }

  it "has at least one page type" do
    expect(page_types.map(&:graphql_name)).to include("EmailLogPage", "UserPage")
  end

  it "gives every page type exactly items, page, perPage, totalCount and totalPages" do
    page_types.each do |type|
      expect(type.fields.keys).to match_array(%w[items page perPage totalCount totalPages]), "#{type.graphql_name} has another shape"
    end
  end

  it "types items as a non-null list of non-null objects" do
    page_types.each do |type|
      expect(type.fields["items"].type.to_type_signature).to match(/\A\[[A-Za-z]+!\]!\z/), "#{type.graphql_name}.items"
    end
  end

  it "never uses a banned name for a list of rows" do
    banned = %w[nodes edges data results itemsList]
    names = object_types.flat_map { |type| type.fields.keys.select { |field| banned.include?(field) }.map { |field| "#{type.graphql_name}.#{field}" } }

    expect(names).to be_empty
  end

  it "gives every query field that returns a page the arguments page and perPage" do
    page_fields = Types::QueryType.fields.values.select { |field| page_types.include?(field.type.unwrap) }

    expect(page_fields).not_to be_empty
    page_fields.each { |field| expect(field.arguments.keys).to include("page", "perPage") }
  end
end
