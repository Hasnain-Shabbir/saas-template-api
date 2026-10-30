require "rails_helper"

RSpec.describe "Read audit log", type: :request do
  # No operation returns another user yet (Layer 3 adds them), so the rule is tested on a throwaway schema that does.
  let(:schema) do
    Class.new(GraphQL::Schema) do
      query(Class.new(Types::BaseObject) do
        graphql_name "ReadAuditTestQuery"
        description "Test only"

        field :user, Types::UserType, null: true, description: "Test only" do
          argument :id, GraphQL::Types::ID, required: true, description: "Test only"
        end
        field :users, [ Types::UserType ], null: false, description: "Test only"

        def user(id:) = User.find(id)
        def users = User.order(:email)
      end)
    end
  end
  let(:admin) { create(:user, :super_admin) }
  let!(:viewed) { create(:user, :with_profile, :with_address) }

  def run(query, reader: admin, **variables)
    schema.execute(query, variables:, context: { current_user: reader, request_id: "req-1" })
  end

  it "logs each group of sensitive fields read from another user, with reader, record, and request id" do
    run("query($id: ID!) { user(id: $id) { phone dateOfBirth city postalCode } }", id: viewed.id)

    expect(ReadAudit.pluck(:field_group)).to contain_exactly("contact", "date_of_birth", "address")
    expect(ReadAudit.all).to all(have_attributes(reader: admin.id, item_type: "User", item_id: viewed.id, request_id: "req-1"))
  end

  it "logs a group once per record per request, however often it is asked for" do
    run("query($id: ID!) { user(id: $id) { a: phone b: phone city state country } }", id: viewed.id)

    expect(ReadAudit.pluck(:field_group)).to contain_exactly("contact", "address")
  end

  it "logs every record of a list" do
    other = create(:user, :with_profile)
    run("{ users { phone } }")

    # The admin is in the list too, but reading their own row is not logged.
    expect(ReadAudit.pluck(:item_id)).to contain_exactly(viewed.id, other.id)
  end

  it "does not log a field that is not sensitive" do
    expect { run("query($id: ID!) { user(id: $id) { id email role firstName lastName } }", id: viewed.id) }.not_to change(ReadAudit, :count)
  end

  it "does not log a person reading their own data" do
    expect { run("query($id: ID!) { user(id: $id) { phone dateOfBirth city } }", reader: viewed, id: viewed.id) }.not_to change(ReadAudit, :count)
  end

  it "stores no value and no query text" do
    run("query($id: ID!) { user(id: $id) { phone dateOfBirth city } }", id: viewed.id)

    stored = ReadAudit.all.map { |row| row.attributes.to_json }.join
    expect(stored).not_to include("+14155552671", "1990-05-21", "San Francisco", "Ada", viewed.email, "query")
  end

  it "does not return the data when the log cannot be written" do
    allow(ReadAudit).to receive(:create!).and_raise(ActiveRecord::StatementInvalid)

    expect { run("query($id: ID!) { user(id: $id) { phone } }", id: viewed.id) }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "marks every personal field of a user as sensitive, and nothing else" do
    expected = {
      "dateOfBirth" => "date_of_birth", "phone" => "contact",
      "addressLine1" => "address", "addressLine2" => "address", "city" => "address",
      "state" => "address", "postalCode" => "address", "country" => "address"
    }
    marked = Types::UserType.fields.select { |_, field| field.extensions.any?(Types::SensitiveFieldExtension) }
                            .transform_values { |field| field.extensions.find { |e| e.is_a?(Types::SensitiveFieldExtension) }.options[:group].to_s }

    expect(marked).to eq(expected)
    expect(marked.values.uniq - ReadAudit::FIELD_GROUPS).to be_empty
  end

  it "records nothing when users read their own data through the real API" do
    user = create(:user, :with_profile, :with_address)

    expect { gql("{ me { phone dateOfBirth city } }", token: token_for(user)) }.not_to change(ReadAudit, :count)
  end

  it "exposes no way to read the read log through GraphQL" do
    expect(SaasTemplateApiSchema.to_definition).not_to match(/read_?audit/i)
  end
end
