require "rails_helper"

RSpec.describe "Impersonation: audit and limits", type: :request do
  let!(:admin) { create(:user, :super_admin, email: "admin@example.test") }
  let!(:member) { create(:user, :with_profile, :with_address, email: "member@example.test") }
  let(:started) { Impersonations::Start.call(impersonator: admin, target: member, reason_category: "support_request").value }
  let(:token) { started.token }
  let(:session) { started.impersonation }

  let(:update_profile) do
    "mutation($i: UpdateProfileInput!) { updateProfile(input: $i) { user { id } errors { message path code } } }"
  end
  let(:profile) { { firstName: "Grace", lastName: "Hopper", dateOfBirth: "1990-05-21", phone: "+14155552671" } }
  let(:update_address) do
    "mutation { updateAddress(input: { addressLine1: \"1 Market Street\", city: \"Oakland\", state: \"CA\", postalCode: \"94105\", country: \"US\" }) { errors { code } } }"
  end

  def error_code(body) = body.dig("errors", 0, "extensions", "code")

  describe "writes" do
    it "records a change made while impersonating under the admin, linked to the session" do
      token
      gql(update_profile, variables: { i: profile }, token:)

      row = AuditVersion.where(item_type: "User", item_id: member.id).order(:created_at, :id).last
      expect(row).to have_attributes(event: "update", whodunnit: admin.id, impersonation_id: session.id)
      expect(row.changed_fields).to include("first_name")
      expect(row.request_id).to eq(response.headers["X-Request-Id"])
      expect(member.reload.first_name).to eq("Grace")
    end

    it "records a normal change of the member under the member, with no session" do
      gql(update_profile, variables: { i: profile }, token: token_for(member))

      row = AuditVersion.where(item_type: "User", item_id: member.id).order(:created_at, :id).last
      expect(row).to have_attributes(whodunnit: member.id, impersonation_id: nil)
    end

    it "does not carry the session into the next request of the same process" do
      gql(update_profile, variables: { i: profile }, token:)
      gql(update_profile, variables: { i: profile.merge(lastName: "Murray") }, token: token_for(member))

      row = AuditVersion.where(item_type: "User", item_id: member.id).order(:created_at, :id).last
      expect(row).to have_attributes(whodunnit: member.id, impersonation_id: nil)
    end

    it "cannot be forged by the client with a parameter" do
      token
      post "/graphql", params: { query: update_profile, variables: { i: profile }, impersonation_id: SecureRandom.uuid },
                       headers: { "Authorization" => "Bearer #{token_for(member)}" }, as: :json

      expect(AuditVersion.where(item_id: member.id).pluck(:impersonation_id).compact).to be_empty
    end
  end

  describe "reads" do
    it "logs a read of the member's sensitive fields under the admin, linked to the session" do
      token
      gql("{ me { phone dateOfBirth city } }", token:)

      rows = ReadAudit.where(item_id: member.id)
      expect(rows.pluck(:field_group)).to contain_exactly("contact", "date_of_birth", "address")
      expect(rows).to all(have_attributes(reader: admin.id, item_type: "User", impersonation_id: session.id))
    end

    it "does not log the member reading their own data in a normal request" do
      gql("{ me { phone dateOfBirth city } }", token: token_for(member))

      expect(ReadAudit.count).to eq(0)
    end
  end

  describe "what an impersonator may run" do
    it "may save the member's profile and address" do
      expect(gql(update_profile, variables: { i: profile }, token:).dig("data", "updateProfile", "errors")).to eq([])
      expect(gql(update_address, token:).dig("data", "updateAddress", "errors")).to eq([])
      expect(member.reload.city).to eq("Oakland")
    end

    it "may read as the member" do
      expect(gql("{ me { id email } }", token:).dig("data", "me", "email")).to eq(member.email)
    end

    {
      "requestPasswordReset" => "mutation { requestPasswordReset(input: { email: \"member@example.test\" }) { success } }",
      "resetPassword" => "mutation { resetPassword(input: { email: \"member@example.test\", code: \"123456\", password: \"another long password\" }) { success } }",
      "requestEmailChange" => "mutation { requestEmailChange(input: { newEmail: \"fresh@example.test\", password: \"correct horse battery\" }) { success } }",
      "confirmEmailChange" => "mutation { confirmEmailChange(input: { code: \"123456\" }) { success } }",
      "acceptTerms" => "mutation { acceptTerms(input: { version: \"x\" }) { errors { code } } }",
      "acceptInvitation" => "mutation { acceptInvitation(input: { token: \"x\", password: \"another long password\" }) { success } }",
      "login" => "mutation { login(input: { email: \"member@example.test\", password: \"correct horse battery\" }) { success } }"
    }.each do |name, query|
      it "refuses #{name} with FORBIDDEN and changes nothing" do
        expect { @body = gql(query, token:) }.not_to change { [ member.reload.encrypted_password, member.email, member.pending_email, member.terms_version ] }

        expect(error_code(@body)).to eq("FORBIDDEN")
        expect(@body.dig("errors", 0, "message")).to eq(Errors::NOT_ALLOWED_WHILE_IMPERSONATING.message)
        expect(@body["data"]).to be_nil
        expect(ActionMailer::Base.deliveries).to be_empty
      end
    end

    it "refuses the admin operations even though the member could never run them" do
      body = gql("mutation { archiveUser(input: { id: \"#{admin.id}\" }) { user { id } } }", token:)

      expect(error_code(body)).to eq("FORBIDDEN")
      expect(admin.reload).not_to be_archived
    end

    it "does not refuse a normal login of the same member, nor the admin's own token" do
      query = "mutation { requestEmailChange(input: { newEmail: \"fresh@example.test\", password: \"correct horse battery\" }) { success errors { code } } }"
      started

      expect(gql(query, token: token_for(member)).dig("data", "requestEmailChange", "success")).to be(true)
      expect(error_code(gql(query, token: token_for(admin)))).to be_nil
    end
  end
end
