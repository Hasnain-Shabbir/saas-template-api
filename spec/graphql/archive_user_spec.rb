require "rails_helper"

RSpec.describe "Archive and unarchive a user", type: :request do
  include ActiveJob::TestHelper

  let!(:admin) { create(:user, :super_admin, email: "admin@example.test") }
  let!(:member) { create(:user, :member, email: "member@example.test", password: "correct horse battery") }

  let(:archive) { "mutation($i: ArchiveUserInput!) { archiveUser(input: $i) { user { id archivedAt } errors { message path code } } }" }
  let(:unarchive) { "mutation($i: UnarchiveUserInput!) { unarchiveUser(input: $i) { user { id archivedAt } errors { message path code } } }" }
  let(:me) { "{ me { id } }" }

  def error_code(body) = body.dig("errors", 0, "extensions", "code")

  def archive_user(id, token: token_for(admin)) = gql(archive, variables: { i: { id: } }, token:)

  def unarchive_user(id, token: token_for(admin)) = gql(unarchive, variables: { i: { id: } }, token:)

  describe "archiveUser" do
    it "archives a member and returns the time" do
      body = archive_user(member.id)

      expect(body.dig("data", "archiveUser", "errors")).to eq([])
      expect(body.dig("data", "archiveUser", "user", "archivedAt")).to be_present
      expect(member.reload).to be_archived
    end

    it "kills the tokens of the member at once" do
      token = token_for(member)
      expect(gql(me, token:).dig("data", "me", "id")).to eq(member.id)

      archive_user(member.id)

      expect(AllowlistedJwt.where(user: member)).not_to exist
      expect(error_code(gql(me, token:))).to eq("UNAUTHENTICATED")
    end

    it "deletes the pending codes of the member" do
      perform_enqueued_jobs { gql(LoginHelpers::LOGIN, variables: { input: { email: member.email, password: "correct horse battery" } }) }
      expect(OneTimeCode.where(user: member)).to exist

      archive_user(member.id)

      expect(OneTimeCode.where(user: member)).not_to exist
    end

    it "keeps the data of the member" do
      archive_user(member.id)

      expect(User.find(member.id)).to have_attributes(email: "member@example.test", role: "member")
    end

    it "is safe to repeat" do
      archive_user(member.id)

      expect { archive_user(member.id) }.not_to change { member.reload.archived_at }
    end

    it "writes an audit row with the actor" do
      archive_user(member.id)

      row = AuditVersion.where(item_type: "User", item_id: member.id).order(:created_at).last
      expect(row.whodunnit).to eq(admin.id)
      expect(row.changed_fields).to include("archived_at")
    end

    it "answers FORBIDDEN when a super_admin archives themselves" do
      body = archive_user(admin.id)

      expect(error_code(body)).to eq("FORBIDDEN")
      expect(admin.reload).not_to be_archived
    end

    it "answers FORBIDDEN when a super_admin archives another super_admin" do
      other = create(:user, :super_admin)

      expect(error_code(archive_user(other.id))).to eq("FORBIDDEN")
      expect(other.reload).not_to be_archived
    end

    it "answers FORBIDDEN to a member, for an existing and an unknown id alike" do
      token = token_for(member)
      other = create(:user)

      expect(error_code(archive_user(other.id, token:))).to eq("FORBIDDEN")
      expect(error_code(archive_user(SecureRandom.uuid, token:))).to eq("FORBIDDEN")
      expect(other.reload).not_to be_archived
    end

    it "answers NOT_FOUND to a super_admin for an unknown id" do
      expect(error_code(archive_user(SecureRandom.uuid))).to eq("NOT_FOUND")
    end

    it "answers UNAUTHENTICATED to nobody, before it looks at the input" do
      expect(error_code(gql(archive))).to eq("UNAUTHENTICATED")
      expect(error_code(gql(archive, variables: { i: {} }))).to eq("UNAUTHENTICATED")
      expect(member.reload).not_to be_archived
    end

    it "answers VALIDATION_FAILED to a super_admin who sends no id" do
      expect(error_code(gql(archive, variables: { i: {} }, token: token_for(admin)))).to eq("VALIDATION_FAILED")
    end
  end

  describe "unarchiveUser" do
    before { Users::Archive.call(user: member) }

    it "restores the member with the same password and role" do
      body = unarchive_user(member.id)

      expect(body.dig("data", "unarchiveUser")).to include("errors" => [])
      expect(body.dig("data", "unarchiveUser", "user", "archivedAt")).to be_nil
      expect(member.reload).to have_attributes(role: "member", archived_at: nil)
      expect(log_in(email: member.email, password: "correct horse battery").dig("data", "verifyLoginCode", "token")).to be_present
    end

    it "writes an audit row with the actor" do
      unarchive_user(member.id)

      row = AuditVersion.where(item_type: "User", item_id: member.id).order(:created_at).last
      expect(row.whodunnit).to eq(admin.id)
      expect(row.changed_fields).to include("archived_at")
    end

    it "answers FORBIDDEN to a member" do
      expect(error_code(unarchive_user(member.id, token: token_for(create(:user))))).to eq("FORBIDDEN")
      expect(member.reload).to be_archived
    end

    it "answers NOT_FOUND to a super_admin for an unknown id" do
      expect(error_code(unarchive_user(SecureRandom.uuid))).to eq("NOT_FOUND")
    end

    it "answers UNAUTHENTICATED to nobody" do
      expect(error_code(gql(unarchive, variables: { i: { id: member.id } }))).to eq("UNAUTHENTICATED")
    end
  end

  describe "an archived user" do
    before { Users::Archive.call(user: member) }

    it "is told at login (step 1) that access is blocked, only with the right password" do
      right = gql(LoginHelpers::LOGIN, variables: { input: { email: member.email, password: "correct horse battery" } })
      wrong = gql(LoginHelpers::LOGIN, variables: { input: { email: member.email, password: "wrong password 1" } })

      expect(right.dig("data", "login", "errors", 0, "code")).to eq("ACCOUNT_ARCHIVED")
      expect(wrong.dig("data", "login", "errors", 0, "code")).to eq("INVALID_CREDENTIALS")
    end

    it "gets no login code by email" do
      expect { request_login_code(email: member.email, password: "correct horse battery") }
        .not_to change { ActionMailer::Base.deliveries.size }
    end

    it "cannot use a login code issued before the archive" do
      Users::Unarchive.call(user: member)
      sent_before = ActionMailer::Base.deliveries.size
      request_login_code(email: member.email, password: "correct horse battery")
      code = login_code_from_email(ActionMailer::Base.deliveries.drop(sent_before))
      Users::Archive.call(user: member)

      expect(verify_login_code(email: member.email, code:).dig("data", "verifyLoginCode", "errors", 0, "code")).to eq("INVALID_CODE")
    end

    it "cannot reset the password even with a valid code (one issued just before the archive)" do
      # Archive deleted the codes, so issue one by hand: it stands for a job that issued it a moment before the archive.
      code =Auth::IssueOneTimeCode.call(user: member, purpose: :password_reset).value
      reset = "mutation($i: ResetPasswordInput!) { resetPassword(input: $i) { success errors { code } } }"

      body = gql(reset, variables: { i: { email: member.email, code:, password: "a brand new password" } })

      expect(body.dig("data", "resetPassword", "errors", 0, "code")).to eq("INVALID_CODE")
      expect(member.reload.valid_password?("correct horse battery")).to be(true)
    end

    it "gets no password reset code, and the request still looks like a success" do
      reset = "mutation($i: RequestPasswordResetInput!) { requestPasswordReset(input: $i) { success errors { code } } }"

      body = nil
      expect { perform_enqueued_jobs { body = gql(reset, variables: { i: { email: member.email } }) } }
        .not_to change { ActionMailer::Base.deliveries.size }
      expect(body.dig("data", "requestPasswordReset", "success")).to be(true)
      expect(OneTimeCode.where(user: member)).not_to exist
    end
  end
end
