require "rails_helper"

RSpec.describe Auditable do
  let(:audited_models) { [ User, Invitation, OnboardingStep ] }

  def versions_of(record) = AuditVersion.where(item_type: record.class.name, item_id: record.id).order(:created_at, :id)

  describe "create, update and destroy" do
    it "records a create with the actor, the model, the record id and the field names" do
      Audit.as("actor-1") { @user = create(:user) }

      row = versions_of(@user).sole
      expect(row).to have_attributes(event: "create", item_type: "User", item_id: @user.id, whodunnit: "actor-1")
      expect(row.changed_fields).to include("email", "encrypted_password")
      expect(row.changed_fields).not_to include("id", "created_at", "updated_at")
      expect(row.created_at).to be_within(5.seconds).of(Time.current)
    end

    it "records an update with only the fields that changed" do
      user = create(:user)

      Audit.as("actor-2") { user.update!(role: "super_admin") }

      row = versions_of(user).last
      expect(row).to have_attributes(event: "update", whodunnit: "actor-2", changed_fields: [ "role" ], value_changes: { "role" => [ "member", "super_admin" ] })
    end

    it "records a destroy with no fields" do
      user = create(:user, :with_profile)

      Audit.as("actor-3") { user.destroy! }

      expect(versions_of(user).last).to have_attributes(event: "destroy", whodunnit: "actor-3", changed_fields: [], value_changes: {})
    end

    it "records invitations and onboarding steps too" do
      user = create(:user)
      invitation = create(:invitation)
      step = OnboardingStep.create!(user:, step_key: "profile", completed_at: Time.current)
      invitation.update!(revoked_at: Time.current)

      expect(versions_of(invitation).pluck(:event)).to eq(%w[create update])
      expect(versions_of(step).pluck(:event)).to eq(%w[create])
    end

    it "records nothing when a save changes nothing" do
      user = create(:user)

      expect { user.save! }.not_to change(AuditVersion, :count)
    end

    it "does not record a change of failed_attempts alone, but records the lock" do
      user = create(:user)

      expect { user.update!(failed_attempts: 3) }.not_to change(AuditVersion, :count)

      user.update!(locked_at: Time.current)
      expect(versions_of(user).last.changed_fields).to include("locked_at")
    end

    it "records nothing for a failed save" do
      user = create(:user)

      expect { user.update(role: nil) }.not_to change(AuditVersion, :count)
      expect { Invitation.create(email: "no-expiry@example.test", role: "member", expires_at: nil) }.not_to change(AuditVersion, :count)
    end

    it "records nothing when the transaction is rolled back" do
      expect do
        ActiveRecord::Base.transaction do
          create(:user)
          raise ActiveRecord::Rollback
        end
      end.not_to change(AuditVersion, :count)
    end

    it "does not record the audited models' neighbours (one-time codes, allowlisted tokens)" do
      user = create(:user)
      before = AuditVersion.count

      OneTimeCode.create!(user:, purpose: "password_reset", code_digest: "digest", expires_at: 10.minutes.from_now)
      AllowlistedJwt.create!(user:, jti: SecureRandom.uuid, exp: 1.hour.from_now)

      expect(AuditVersion.count).to eq(before)
    end
  end

  describe "sensitive values" do
    it "never stores a password, digest, token, or personal value" do
      user = create(:user, :with_profile, :with_address, password: "hunter2 hunter2 hunter2")
      user.update!(first_name: "Grace", phone: "+14155550000", password: "another long password")
      user.update!(email: "changed@example.test", pending_email: "pending@example.test", previous_email: "old@example.test")
      invitation = create(:invitation, email: "secret-invitee@example.test", token_digest: "tokendigest123")
      invitation.update!(token_digest: "tokendigest456")

      stored = AuditVersion.all.map { |row| row.attributes.to_json }.join
      [
        "hunter2", "another long password", user.encrypted_password, "Ada", "Lovelace", "Grace", "1990-05-21", "+1415555",
        "1 Market Street", "San Francisco", "94105", "@example.test", "tokendigest"
      ].each { |secret| expect(stored).not_to include(secret) }
    end

    it "stores the name of a sensitive field, but never its value" do
      user = create(:user)
      user.update!(first_name: "Grace", phone: "+14155550000")

      row = versions_of(user).last
      expect(row.changed_fields).to contain_exactly("first_name", "phone")
      expect(row.value_changes).to eq({})
    end

    it "lists no sensitive field in any value allowlist" do
      sensitive = /passw|token|digest|secret|code|otp|email|phone|name|birth|address|city|state|postal|country|api_key|secret_key|private_key|encryption_key/
      audited_models.each do |model|
        expect(model.audited_value_fields.grep(sensitive)).to be_empty, "#{model} stores a sensitive value"
        expect(model.audited_value_fields & Array(model.encrypted_attributes).map(&:to_s)).to be_empty
      end
    end

    it "lists only real columns" do
      audited_models.each { |model| expect(model.audited_value_fields - model.column_names).to be_empty }
    end
  end

  describe "the actor outside a request" do
    it "is labelled system when nobody set one" do
      user = create(:user)

      expect(versions_of(user).sole.whodunnit).to eq("system:unknown")
    end

    it "is labelled console in the Rails console" do
      stub_const("Rails::Console", Class.new)
      user = create(:user)

      expect(versions_of(user).sole.whodunnit).to eq("system:console")
    end

    it "goes back to the old actor after the block" do
      Audit.as("outer") { Audit.as("inner") { create(:user) } }
      user = create(:user)

      expect(AuditVersion.order(:created_at).first.whodunnit).to eq("inner")
      expect(versions_of(user).sole.whodunnit).to eq("system:unknown")
    end
  end
end
