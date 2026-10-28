require "rails_helper"

# Guards against someone removing a limit. Raising one needs the owner's approval (see graphql-operations.md).
RSpec.describe SaasTemplateApiSchema do
  it "keeps depth, complexity, and size limits set" do
    expect(described_class.max_depth).to be <= 8
    expect(described_class.max_complexity).to be <= 200
    expect(described_class.max_query_string_tokens).to be <= 2000
  end

  it "rejects a query over the complexity limit" do
    fields = Array.new(100) { |i| "a#{i}: me { id email }" }.join(" ")
    result = described_class.execute("{ #{fields} }")

    expect(result.to_h["errors"].to_s).to match(/complexity/i)
  end
end
