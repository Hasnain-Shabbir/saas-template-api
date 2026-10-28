require "rails_helper"

RSpec.describe AllowlistedJwt do
  let(:user) { create(:user) }

  it "needs a user, a jti, and an expiry" do
    jwt = described_class.new

    expect(jwt).not_to be_valid
    expect(jwt.errors.attribute_names).to include(:user, :jti, :exp)
  end

  it "enforces a unique jti in the database" do
    user.allowlisted_jwts.create!(jti: "same", exp: 1.hour.from_now)
    row = { jti: "same", exp: 1.hour.from_now, user_id: user.id, created_at: Time.current, updated_at: Time.current }

    expect { described_class.insert_all!([ row ]) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
