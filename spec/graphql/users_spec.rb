require "rails_helper"

RSpec.describe "Users list query", type: :request do
  let!(:admin) { create(:user, :super_admin, email: "admin@example.test", created_at: Time.zone.local(2026, 3, 1, 8)) }
  let!(:member) { create(:user, :member, email: "member@example.test", created_at: Time.zone.local(2026, 2, 5, 9)) }
  let!(:ada) do
    create(:user, :member, :with_profile, :with_address, :with_terms, email: "ada@example.test", first_name: "Ada", last_name: "Lovelace",
                                                                       created_at: Time.zone.local(2026, 1, 10, 12))
  end

  let(:list) do
    "query($role: UserListRole, $createdFrom: ISO8601Date, $createdTo: ISO8601Date, $search: String, $page: Int, $perPage: Int) {
       users(role: $role, createdFrom: $createdFrom, createdTo: $createdTo, search: $search, page: $page, perPage: $perPage) {
         page perPage totalCount totalPages
         items { id email firstName lastName role locked onboardingCompleted createdAt }
       }
     }"
  end

  def error_code(body) = body.dig("errors", 0, "extensions", "code")

  def ids(body) = body.dig("data", "users", "items").pluck("id")

  describe "users" do
    it "returns the page for a super_admin, newest first, with the row fields" do
      stub_onboarding_steps(*real_onboarding_steps)
      Onboarding::Sync.call(user: ada) # ada has a profile, an address and the terms, so all three steps are saved for her
      body = gql(list, token: token_for(admin))

      page = body.dig("data", "users")
      expect(page).to include("page" => 1, "perPage" => ValidationRules::PAGE_SIZE_DEFAULT, "totalCount" => 2, "totalPages" => 1)
      expect(ids(body)).to eq([ member.id, ada.id ])
      row = page["items"].find { |item| item["id"] == ada.id }
      expect(row).to include("email" => "ada@example.test", "firstName" => "Ada", "lastName" => "Lovelace", "role" => "MEMBER",
                             "locked" => false, "onboardingCompleted" => true)
      expect(page["items"].find { |item| item["id"] == member.id }["onboardingCompleted"]).to be(false)
    end

    it "never lists a super_admin, whatever the filters say" do
      create(:user, :super_admin, email: "second-admin@example.test", first_name: "Ada")
      token = token_for(admin)

      expect(ids(gql(list, token:))).not_to include(admin.id)
      expect(gql(list, token:).dig("data", "users", "totalCount")).to eq(2)
      expect(ids(gql(list, variables: { search: "admin" }, token:))).to be_empty
      expect(ids(gql(list, variables: { search: "ada" }, token:))).to eq([ ada.id ])
      expect(Types::UserListRoleEnum.values.keys).to eq([ "MEMBER" ])
    end

    it "shows a locked user as locked" do
      ada.update_columns(locked_at: Time.current)

      body = gql(list, variables: { search: "ada" }, token: token_for(admin))
      expect(body.dig("data", "users", "items", 0, "locked")).to be(true)
    end

    it "filters by role, date range and search" do
      token = token_for(admin)

      expect(ids(gql(list, variables: { role: "MEMBER" }, token:))).to eq([ member.id, ada.id ])
      expect(ids(gql(list, variables: { createdTo: "2026-01-31" }, token:))).to eq([ ada.id ])
      expect(ids(gql(list, variables: { createdFrom: "2026-02-01", role: "MEMBER" }, token:))).to eq([ member.id ])
      expect(ids(gql(list, variables: { search: "LOVEL" }, token:))).to eq([ ada.id ])
    end

    it "pages the result and lowers a size that is too big" do
      token = token_for(admin)

      body = gql(list, variables: { perPage: 1, page: 2 }, token:)
      expect(body.dig("data", "users")).to include("page" => 2, "perPage" => 1, "totalPages" => 2)
      expect(ids(body).size).to eq(1)

      huge = gql(list, variables: { perPage: 1_000_000, page: -4 }, token:)
      expect(huge.dig("data", "users")).to include("page" => 1, "perPage" => ValidationRules::PAGE_SIZE_MAX)
    end

    it "does not read the user's personal data, so it writes no read audit row" do
      expect(Types::UserSummaryType.fields.keys).not_to include("dateOfBirth", "phone", "addressLine1", "city", "postalCode", "termsVersion")

      expect { gql(list, token: token_for(admin)) }.not_to change(ReadAudit, :count)
    end

    it "loads the onboarding steps once, not once per user" do
      create_list(:user, 3)
      token = token_for(admin)

      queries = []
      callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?("onboarding_steps") }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { gql(list, token:) }

      expect(queries.size).to eq(1)
    end

    it "answers FORBIDDEN to a member, whatever they send" do
      token = token_for(member)

      expect(error_code(gql(list, token:))).to eq("FORBIDDEN")
      expect(error_code(gql(list, variables: { search: "'; DROP TABLE users; --", perPage: 3 }, token:))).to eq("FORBIDDEN")
      expect(gql(list, token:)["data"]).to be_nil
    end

    it "answers UNAUTHENTICATED to nobody, before it looks at the input" do
      expect(error_code(gql(list))).to eq("UNAUTHENTICATED")
      expect(error_code(gql(list, variables: { role: "NOT_A_ROLE" }))).to eq("UNAUTHENTICATED")
    end

    it "answers UNAUTHENTICATED to a garbage token" do
      expect(error_code(gql(list, token: "not.a.token"))).to eq("UNAUTHENTICATED")
    end

    it "answers UNAUTHENTICATED to a token after logout" do
      token = token_for(admin)
      gql("mutation { logout(input: {}) { success } }", token:)

      expect(error_code(gql(list, token:))).to eq("UNAUTHENTICATED")
    end

    it "answers VALIDATION_FAILED to a super_admin who sends a bad role, or SUPER_ADMIN" do
      expect(error_code(gql(list, variables: { role: "NOT_A_ROLE" }, token: token_for(admin)))).to eq("VALIDATION_FAILED")
      expect(error_code(gql(list, variables: { role: "SUPER_ADMIN" }, token: token_for(admin)))).to eq("VALIDATION_FAILED")
    end
  end
end
