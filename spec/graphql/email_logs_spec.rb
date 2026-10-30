require "rails_helper"

RSpec.describe "Email log queries", type: :request do
  let(:admin) { create(:user, :super_admin) }
  let(:member) { create(:user, :member) }
  let!(:sent) do
    create(:email_log, recipient: "jo@example.test", status: "sent", body: "Your code is: 042917", created_at: Time.zone.local(2026, 1, 10, 12))
  end
  let!(:failed) do
    create(:email_log, recipient: "sam@other.test", status: "failed", sent_at: nil, body: "Open https://app.example.test/x?token=live",
                       created_at: Time.zone.local(2026, 2, 5, 12))
  end

  let(:list) do
    "query($from: ISO8601Date, $to: ISO8601Date, $status: EmailLogStatus, $search: String, $page: Int, $perPage: Int) {
       emailLogs(from: $from, to: $to, status: $status, search: $search, page: $page, perPage: $perPage) {
         page perPage totalCount totalPages
         items { id recipient mailer action subject status sentAt createdAt }
       }
     }"
  end
  let(:list_with_body) { "{ emailLogs { items { id body } } }" }
  let(:one) { "query($id: ID!) { emailLog(id: $id) { id recipient body status } }" }

  def error_code(body) = body.dig("errors", 0, "extensions", "code")

  describe "emailLogs" do
    it "returns the page for a super_admin, newest first" do
      body = gql(list, token: token_for(admin))

      page = body.dig("data", "emailLogs")
      expect(page).to include("page" => 1, "perPage" => ValidationRules::PAGE_SIZE_DEFAULT, "totalCount" => 2, "totalPages" => 1)
      expect(page["items"].pluck("id")).to eq([ failed.id, sent.id ])
      expect(page["items"].first).to include("recipient" => "sam@other.test", "status" => "FAILED", "sentAt" => nil)
    end

    it "filters by status, date range and part of an address" do
      token = token_for(admin)

      expect(gql(list, variables: { status: "SENT" }, token:).dig("data", "emailLogs", "items").pluck("id")).to eq([ sent.id ])
      expect(gql(list, variables: { from: "2026-02-01" }, token:).dig("data", "emailLogs", "items").pluck("id")).to eq([ failed.id ])
      expect(gql(list, variables: { to: "2026-01-31" }, token:).dig("data", "emailLogs", "items").pluck("id")).to eq([ sent.id ])
      expect(gql(list, variables: { search: "OTHER.test" }, token:).dig("data", "emailLogs", "items").pluck("id")).to eq([ failed.id ])
    end

    it "pages the result and lowers a size that is too big" do
      token = token_for(admin)

      body = gql(list, variables: { perPage: 1, page: 2 }, token:)
      expect(body.dig("data", "emailLogs")).to include("page" => 2, "perPage" => 1, "totalPages" => 2)
      expect(body.dig("data", "emailLogs", "items").pluck("id")).to eq([ sent.id ])

      huge = gql(list, variables: { perPage: 1_000_000, page: -4 }, token:)
      expect(huge.dig("data", "emailLogs")).to include("page" => 1, "perPage" => ValidationRules::PAGE_SIZE_MAX)
    end

    it "does not return the error class (a class name is never sent to a client)" do
      expect(Types::EmailLogType.fields.keys).not_to include("errorClass", "error_class")
    end

    it "answers FORBIDDEN to a member, whatever they send" do
      token = token_for(member)

      expect(error_code(gql(list, token:))).to eq("FORBIDDEN")
      expect(error_code(gql(list, variables: { search: "'; DROP TABLE email_logs; --", perPage: 3 }, token:))).to eq("FORBIDDEN")
      expect(gql(list, token:)["data"]).to be_nil
    end

    it "answers UNAUTHENTICATED to nobody, before it looks at the input" do
      expect(error_code(gql(list))).to eq("UNAUTHENTICATED")
      expect(error_code(gql(list, variables: { status: "NOT_A_STATUS" }))).to eq("UNAUTHENTICATED")
    end

    it "answers UNAUTHENTICATED to a garbage token" do
      expect(error_code(gql(list, token: "not.a.token"))).to eq("UNAUTHENTICATED")
    end

    it "answers UNAUTHENTICATED to a token after logout" do
      token = token_for(admin)
      gql("mutation { logout(input: {}) { success } }", token:)

      expect(error_code(gql(list, token:))).to eq("UNAUTHENTICATED")
    end

    it "refuses an unknown status" do
      body = gql(list, variables: { status: "QUEUED" }, token: token_for(admin))

      expect(body["errors"]).to be_present
      expect(body["data"]).to be_nil
    end

    it "treats SQL in the search as text" do
      body = gql(list, variables: { search: "%' OR 1=1 --" }, token: token_for(admin))

      expect(body.dig("data", "emailLogs", "items")).to eq([])
      expect(EmailLog.count).to eq(2)
    end

    it "does not run more queries as the page grows" do
      token = token_for(admin)
      create_list(:email_log, 3)
      few = count_queries { gql(list_with_body, token:) }
      create_list(:email_log, 10)
      many = count_queries { gql(list_with_body, token:) }

      # Each body read adds one read audit insert and one lookup of the "seen" row, so compare the reads of the log itself.
      expect(many[:selects_of_email_logs]).to eq(few[:selects_of_email_logs])
    end
  end

  describe "emailLog" do
    it "returns one entry for a super_admin, with the body as sent" do
      body = gql(one, variables: { id: sent.id }, token: token_for(admin))

      expect(body.dig("data", "emailLog")).to include("id" => sent.id, "recipient" => "jo@example.test", "body" => "Your code is: 042917", "status" => "SENT")
    end

    it "answers NOT_FOUND for an id that does not exist and for text that is not an id" do
      token = token_for(admin)

      expect(error_code(gql(one, variables: { id: SecureRandom.uuid }, token:))).to eq("NOT_FOUND")
      expect(error_code(gql(one, variables: { id: "not-an-id" }, token:))).to eq("NOT_FOUND")
    end

    it "answers FORBIDDEN to a member, also for an id that exists and one that does not" do
      token = token_for(member)

      expect(error_code(gql(one, variables: { id: sent.id }, token:))).to eq("FORBIDDEN")
      expect(error_code(gql(one, variables: { id: SecureRandom.uuid }, token:))).to eq("FORBIDDEN")
    end

    it "answers UNAUTHENTICATED to nobody" do
      expect(error_code(gql(one, variables: { id: sent.id }))).to eq("UNAUTHENTICATED")
    end
  end

  describe "read audit" do
    it "records who read the body of each entry, once per entry per request" do
      gql("{ a: emailLogs { items { body } } b: emailLogs { items { body } } }", token: token_for(admin))

      rows = ReadAudit.where(field_group: "email_body")
      expect(rows.pluck(:item_id)).to contain_exactly(sent.id, failed.id)
      expect(rows).to all(have_attributes(reader: admin.id, item_type: "EmailLog"))
      expect(rows.pluck(:request_id)).to all(be_present)
    end

    it "records the read of a single entry" do
      gql(one, variables: { id: sent.id }, token: token_for(admin))

      expect(ReadAudit.where(field_group: "email_body").pluck(:item_id)).to eq([ sent.id ])
    end

    it "records nothing when the body is not asked for" do
      gql(list, token: token_for(admin))

      expect(ReadAudit.count).to eq(0)
    end

    it "records nothing when a member is refused" do
      gql(list_with_body, token: token_for(member))

      expect(ReadAudit.count).to eq(0)
    end

    it "stores no part of the body in the audit row" do
      gql(list_with_body, token: token_for(admin))

      stored = ReadAudit.all.map { |row| row.attributes.values.join(" ") }.join(" ")
      expect(stored).not_to include("042917", "live")
    end

    it "does not return the body when the audit row cannot be written" do
      allow(Audit::RecordRead).to receive(:call).and_raise(ActiveRecord::StatementInvalid)

      body = gql(list_with_body, token: token_for(admin))

      expect(body.to_json).not_to include("042917")
      expect(error_code(body)).to eq("INTERNAL_ERROR")
    end
  end

  def count_queries
    selects = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      selects += 1 if payload[:sql].match?(/\ASELECT .* FROM "email_logs"/m)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    { selects_of_email_logs: selects }
  end
end
