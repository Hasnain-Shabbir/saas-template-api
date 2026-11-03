require "rails_helper"

RSpec.describe "Revoke and grant the access of a user", type: :request do
  include ActiveJob::TestHelper

  let!(:admin) { create(:user, :super_admin, email: "admin@example.test") }
  let!(:member) { create(:user, :member, email: "member@example.test", password: "correct horse battery") }

  let(:revoke) { "mutation($i: RevokeUserAccessInput!) { revokeUserAccess(input: $i) { user { id accessRevokedAt archivedAt } errors { message path code } } }" }
  let(:grant) { "mutation($i: GrantUserAccessInput!) { grantUserAccess(input: $i) { user { id accessRevokedAt } errors { message path code } } }" }
  let(:me) { "{ me { id } }" }

  def error_code(body) = body.dig("errors", 0, "extensions", "code")

  def revoke_access(id, token: token_for(admin)) = gql(revoke, variables: { i: { id: } }, token:)

  def grant_access(id, token: token_for(admin)) = gql(grant, variables: { i: { id: } }, token:)

  describe "revokeUserAccess" do
    it "revokes the access of a member and returns the time" do
      body = revoke_access(member.id)

      expect(body.dig("data", "revokeUserAccess", "errors")).to eq([])
      expect(body.dig("data", "revokeUserAccess", "user", "accessRevokedAt")).to be_present
      expect(member.reload).to be_access_revoked
    end

    it "does not archive the member" do
      body = revoke_access(member.id)

      expect(body.dig("data", "revokeUserAccess", "user", "archivedAt")).to be_nil
      expect(member.reload).not_to be_archived
    end

    it "keeps the member in the normal users list" do
      revoke_access(member.id)

      list = gql("{ users { items { id accessRevokedAt } } }", token: token_for(admin))

      expect(list.dig("data", "users", "items").map { |row| row["id"] }).to include(member.id)
    end

    it "kills the tokens of the member at once" do
      token = token_for(member)
      expect(gql(me, token:).dig("data", "me", "id")).to eq(member.id)

      revoke_access(member.id)

      expect(AllowlistedJwt.where(user: member)).not_to exist
      expect(error_code(gql(me, token:))).to eq("UNAUTHENTICATED")
    end

    it "deletes the pending codes of the member" do
      perform_enqueued_jobs { gql(LoginHelpers::LOGIN, variables: { input: { email: member.email, password: "correct horse battery" } }) }
      expect(OneTimeCode.where(user: member)).to exist

      revoke_access(member.id)

      expect(OneTimeCode.where(user: member)).not_to exist
    end

    it "keeps the data of the member" do
      revoke_access(member.id)

      expect(User.find(member.id)).to have_attributes(email: "member@example.test", role: "member")
    end

    it "is safe to repeat" do
      revoke_access(member.id)

      expect { revoke_access(member.id) }.not_to change { member.reload.access_revoked_at }
    end

    it "writes an audit row with the actor" do
      revoke_access(member.id)

      row = AuditVersion.where(item_type: "User", item_id: member.id).order(:created_at).last
      expect(row.whodunnit).to eq(admin.id)
      expect(row.changed_fields).to include("access_revoked_at")
    end

    it "answers FORBIDDEN when a super_admin revokes themselves" do
      expect(error_code(revoke_access(admin.id))).to eq("FORBIDDEN")
      expect(admin.reload).not_to be_access_revoked
    end

    it "answers FORBIDDEN when a super_admin revokes another super_admin" do
      other = create(:user, :super_admin)

      expect(error_code(revoke_access(other.id))).to eq("FORBIDDEN")
      expect(other.reload).not_to be_access_revoked
    end

    it "answers FORBIDDEN to a member, for an existing and an unknown id alike" do
      token = token_for(member)
      other = create(:user)

      expect(error_code(revoke_access(other.id, token:))).to eq("FORBIDDEN")
      expect(error_code(revoke_access(SecureRandom.uuid, token:))).to eq("FORBIDDEN")
      expect(other.reload).not_to be_access_revoked
    end

    it "answers NOT_FOUND to a super_admin for an unknown id" do
      expect(error_code(revoke_access(SecureRandom.uuid))).to eq("NOT_FOUND")
    end

    it "answers UNAUTHENTICATED to nobody, before it looks at the input" do
      expect(error_code(gql(revoke))).to eq("UNAUTHENTICATED")
      expect(error_code(gql(revoke, variables: { i: {} }))).to eq("UNAUTHENTICATED")
      expect(member.reload).not_to be_access_revoked
    end

    it "answers VALIDATION_FAILED to a super_admin who sends no id" do
      expect(error_code(gql(revoke, variables: { i: {} }, token: token_for(admin)))).to eq("VALIDATION_FAILED")
    end
  end

  describe "grantUserAccess" do
    before { Users::RevokeAccess.call(user: member) }

    it "gives the access back with the same password and role" do
      body = grant_access(member.id)

      expect(body.dig("data", "grantUserAccess")).to include("errors" => [])
      expect(body.dig("data", "grantUserAccess", "user", "accessRevokedAt")).to be_nil
      expect(member.reload).to have_attributes(role: "member", access_revoked_at: nil)
      expect(log_in(email: member.email, password: "correct horse battery").dig("data", "verifyLoginCode", "token")).to be_present
    end

    it "does not bring back the old tokens" do
      Users::GrantAccess.call(user: member)

      expect(AllowlistedJwt.where(user: member)).not_to exist
    end

    it "does not unarchive an archived member" do
      Users::Archive.call(user: member)

      grant_access(member.id)

      expect(member.reload).to be_archived
      expect(member).not_to be_access_revoked
      expect(log_in(email: member.email, password: "correct horse battery").dig("data", "login", "errors", 0, "code")).to eq("ACCOUNT_ARCHIVED")
    end

    it "writes an audit row with the actor" do
      grant_access(member.id)

      row = AuditVersion.where(item_type: "User", item_id: member.id).order(:created_at).last
      expect(row.whodunnit).to eq(admin.id)
      expect(row.changed_fields).to include("access_revoked_at")
    end

    it "answers FORBIDDEN to a member" do
      expect(error_code(grant_access(member.id, token: token_for(create(:user))))).to eq("FORBIDDEN")
      expect(member.reload).to be_access_revoked
    end

    it "answers NOT_FOUND to a super_admin for an unknown id" do
      expect(error_code(grant_access(SecureRandom.uuid))).to eq("NOT_FOUND")
    end

    it "answers UNAUTHENTICATED to nobody" do
      expect(error_code(gql(grant, variables: { i: { id: member.id } }))).to eq("UNAUTHENTICATED")
    end
  end

  describe "a user whose access is revoked" do
    before { Users::RevokeAccess.call(user: member) }

    it "is told at login (step 1) that access is revoked, only with the right password" do
      right = gql(LoginHelpers::LOGIN, variables: { input: { email: member.email, password: "correct horse battery" } })
      wrong = gql(LoginHelpers::LOGIN, variables: { input: { email: member.email, password: "wrong password 1" } })

      expect(right.dig("data", "login", "errors", 0, "code")).to eq("ACCESS_REVOKED")
      expect(wrong.dig("data", "login", "errors", 0, "code")).to eq("INVALID_CREDENTIALS")
    end

    it "gets no login code by email" do
      expect { request_login_code(email: member.email, password: "correct horse battery") }
        .not_to change { ActionMailer::Base.deliveries.size }
    end

    it "cannot use a login code issued before the revoke" do
      Users::GrantAccess.call(user: member)
      sent_before = ActionMailer::Base.deliveries.size
      request_login_code(email: member.email, password: "correct horse battery")
      code = login_code_from_email(ActionMailer::Base.deliveries.drop(sent_before))
      Users::RevokeAccess.call(user: member)

      expect(verify_login_code(email: member.email, code:).dig("data", "verifyLoginCode", "errors", 0, "code")).to eq("INVALID_CODE")
    end

    it "cannot reset the password even with a valid code (one issued just before the revoke)" do
      code = Auth::IssueOneTimeCode.call(user: member, purpose: :password_reset).value
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
