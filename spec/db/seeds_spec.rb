require "rails_helper"

RSpec.describe "db/seeds.rb" do
  let(:email) { "root@example.test" }
  let(:password) { "correct horse battery" }

  def seed(env)
    stub_const("ENV", ENV.to_h.merge(env))
    load Rails.root.join("db/seeds.rb")
  end

  it "creates a super_admin from the environment" do
    seed("SUPER_ADMIN_EMAIL" => email, "SUPER_ADMIN_PASSWORD" => password)

    user = User.find_by!(email:)
    expect(user).to be_super_admin
    expect(user.valid_password?(password)).to be(true)
  end

  it "records the audit log as the seed actor" do
    seed("SUPER_ADMIN_EMAIL" => email, "SUPER_ADMIN_PASSWORD" => password)

    expect(AuditVersion.where(item_type: "User", item_id: User.find_by!(email:).id).sole.whodunnit).to eq("system:seed")
  end

  it "can run twice without a second user" do
    2.times { seed("SUPER_ADMIN_EMAIL" => email, "SUPER_ADMIN_PASSWORD" => password) }

    expect(User.where(email:).count).to eq(1)
  end

  it "never changes an existing user" do
    existing = create(:user, email:, password: "another long password")

    seed("SUPER_ADMIN_EMAIL" => email, "SUPER_ADMIN_PASSWORD" => password)

    existing.reload
    expect(existing).to be_member
    expect(existing.valid_password?("another long password")).to be(true)
  end

  it "creates nothing when the variables are missing" do
    expect { seed("SUPER_ADMIN_EMAIL" => "", "SUPER_ADMIN_PASSWORD" => "") }
      .to output(/Skipped the super admin/).to_stdout
    expect(User.count).to eq(0)
  end

  it "refuses a weak password instead of creating the account" do
    expect { seed("SUPER_ADMIN_EMAIL" => email, "SUPER_ADMIN_PASSWORD" => "short") }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(User.count).to eq(0)
  end
end
