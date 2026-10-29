require "rails_helper"

RSpec.describe AuthGate do
  def required?(query, operation_name: nil) = described_class.login_required?(query, operation_name:)

  it "does not need a login for a public operation" do
    expect(required?("mutation { login(input: {}) { token } }")).to be(false)
    expect(required?("mutation { signUp(input: {}) { token } }")).to be(false)
  end

  it "needs a login for any other operation, query or mutation" do
    expect(required?("mutation { inviteUser(input: {}) { success } }")).to be(true)
    expect(required?("{ me { id } }")).to be(true)
    expect(required?("{ somethingUnknown }")).to be(true)
  end

  it "cannot be fooled by an alias, a fragment, or a public operation next to a protected one" do
    expect(required?("mutation { login: inviteUser(input: {}) { success } }")).to be(true)
    expect(required?("mutation { ...F } fragment F on Mutation { revokeInvitation(input: {}) { success } }")).to be(true)
    expect(required?("mutation { ... on Mutation { resendInvitation(input: {}) { success } } }")).to be(true)
    expect(required?("mutation { login(input: {}) { token } inviteUser(input: {}) { success } }")).to be(true)
  end

  it "looks only at the operation that runs" do
    query = "query A { me { id } } mutation B { login(input: {}) { token } }"

    expect(required?(query, operation_name: "A")).to be(true)
    expect(required?(query, operation_name: "B")).to be(false)
    expect(required?(query)).to be(false) # no single operation: GraphQL rejects it
  end

  it "leaves a query that cannot be parsed to GraphQL (BAD_REQUEST)" do
    expect(required?("mutation {")).to be(false)
  end

  it "lets introspection fields through" do
    expect(required?("{ __typename }")).to be(false)
  end
end
