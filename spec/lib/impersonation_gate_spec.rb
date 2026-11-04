require "rails_helper"

RSpec.describe ImpersonationGate do
  # Every mutation must be decided on purpose: allowed in the gate, or listed here as blocked. A new mutation fails the coverage
  # test below until it is added to one of the two lists.
  BLOCKED_MUTATIONS = %w[
    signUp login verifyLoginCode requestPasswordReset resetPassword requestEmailChange confirmEmailChange
    inviteUser acceptInvitation revokeInvitation resendInvitation
    archiveUser unarchiveUser revokeUserAccess grantUserAccess
    acceptTerms startImpersonation
  ].freeze

  def blocked?(query, operation_name: nil) = described_class.blocked?(query, operation_name:)

  it "lets the allowed mutations through" do
    described_class::ALLOWED_MUTATIONS.each do |name|
      expect(blocked?("mutation { #{name}(input: {}) { errors { code } } }")).to be(false)
    end
  end

  it "blocks every other mutation, including the public ones" do
    BLOCKED_MUTATIONS.each do |name|
      expect(blocked?("mutation { #{name}(input: {}) { errors { code } } }")).to be(true), "#{name} was not blocked"
    end
  end

  it "blocks a mutation next to an allowed one, through an alias, and through a fragment" do
    expect(blocked?("mutation { updateProfile(input: {}) { errors { code } } resetPassword(input: {}) { success } }")).to be(true)
    expect(blocked?("mutation { updateProfile: resetPassword(input: {}) { success } }")).to be(true)
    expect(blocked?("mutation { ...F } fragment F on Mutation { requestEmailChange(input: {}) { success } }")).to be(true)
    expect(blocked?("mutation { ... on Mutation { acceptTerms(input: {}) { errors { code } } } }")).to be(true)
  end

  it "blocks a mutation it does not know" do
    expect(blocked?("mutation { somethingNew(input: {}) { success } }")).to be(true)
  end

  it "never blocks reading" do
    expect(blocked?("{ me { id } }")).to be(false)
    expect(blocked?("query { users { items { id } } }")).to be(false)
    expect(blocked?("{ __typename }")).to be(false)
  end

  it "looks only at the operation that runs" do
    query = "query A { me { id } } mutation B { resetPassword(input: {}) { success } }"

    expect(blocked?(query, operation_name: "A")).to be(false)
    expect(blocked?(query, operation_name: "B")).to be(true)
  end

  it "leaves a query that cannot be parsed to GraphQL (BAD_REQUEST)" do
    expect(blocked?("mutation {")).to be(false)
  end

  it "has a decision for every mutation in the schema" do
    in_schema = SaasTemplateApiSchema.mutation.fields.keys
    decided = described_class::ALLOWED_MUTATIONS + BLOCKED_MUTATIONS

    expect(in_schema - decided).to eq([])
    expect(decided - in_schema).to eq([])
  end
end
