require "rails_helper"

RSpec.describe "Audit log", type: :request do
  let(:password) { "correct horse battery" }
  let(:user) { create(:user) }
  let(:token) { token_for(user) }
  let(:update_profile) do
    "mutation($i: UpdateProfileInput!) { updateProfile(input: $i) { user { id } errors { message path code } } }"
  end
  let(:profile) { { firstName: "Ada", lastName: "Lovelace", dateOfBirth: "1990-05-21", phone: "+14155552671" } }
  let(:sign_up) { "mutation($input: SignUpInput!) { signUp(input: $input) { token user { id } errors { message path code } } }" }

  def rows_of(record) = AuditVersion.where(item_type: record.class.name, item_id: record.id).order(:created_at, :id)

  it "records a logged-in change with the user id as the actor, and the request id" do
    token # the user and its token exist before the request under test
    gql(update_profile, variables: { i: profile }, token:)

    row = rows_of(user).last
    expect(row).to have_attributes(event: "update", whodunnit: user.id)
    expect(row.changed_fields).to contain_exactly("first_name", "last_name", "date_of_birth", "phone")
    expect(row.request_id).to be_present.and eq(response.headers["X-Request-Id"])
  end

  it "records a change by nobody logged in as anonymous", :public_sign_up do
    body = gql(sign_up, variables: { input: { email: "new@example.test", password: } })

    new_user = User.find(body.dig("data", "signUp", "user", "id"))
    expect(rows_of(new_user).sole).to have_attributes(event: "create", whodunnit: "anonymous", request_id: response.headers["X-Request-Id"])
  end

  it "does not let a client choose the actor or the request id" do
    token
    gql(update_profile, variables: { i: profile }, token:)
    post "/graphql", params: { query: update_profile, variables: { i: profile.merge(lastName: "King") }, whodunnit: "admin", request_id: "forged" },
                     headers: { "Authorization" => "Bearer #{token}", "X-Whodunnit" => "admin" }, as: :json

    expect(rows_of(user).last.whodunnit).to eq(user.id)
    expect(rows_of(user).last.request_id).not_to eq("forged")
  end

  it "records nothing for a refused request" do
    token

    expect { gql(update_profile, variables: { i: profile }) }.not_to change(AuditVersion, :count)
    expect { gql(update_profile, variables: { i: profile.merge(phone: "nope") }, token:) }.not_to change(AuditVersion, :count)
  end

  it "does not carry the actor of one request into the next" do
    token
    gql(update_profile, variables: { i: profile }, token:)

    expect(Audit.fallback_actor).to eq("system:unknown")
  end

  it "keeps personal values out of the log lines that write the audit log, and stores none of them" do
    token
    io = StringIO.new
    logger = Logger.new(io)
    original = ActiveSupport::LogSubscriber.logger
    ActiveSupport::LogSubscriber.logger = logger
    begin
      gql(update_profile, variables: { i: profile }, token:)
    ensure
      ActiveSupport::LogSubscriber.logger = original
    end

    audit_lines = io.string.lines.grep(/audit_versions/)
    expect(audit_lines).not_to be_empty
    expect(audit_lines.join).not_to include("Ada", "Lovelace", "1990-05-21", "+14155552671", user.email)
    expect(AuditVersion.all.map { |row| row.attributes.to_json }.join).not_to include("Ada", "Lovelace", "1990-05-21", "+14155552671")
  end

  it "keeps the parameter filters working" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    params = { "query" => 'mutation { login(input: { password: "s3cret-pass" }) { token } }', "variables" => { "input" => { "password" => "s3cret-pass" } } }

    expect(filter.filter(params).to_s).not_to include("s3cret-pass")
  end

  it "exposes no way to read the audit log through GraphQL" do
    expect(SaasTemplateApiSchema.to_definition).not_to match(/audit|version/i)
  end
end
