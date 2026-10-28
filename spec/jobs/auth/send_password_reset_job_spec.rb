require "rails_helper"

RSpec.describe Auth::SendPasswordResetJob, type: :job do
  include ActiveJob::TestHelper

  let!(:user) { create(:user) }

  before { ActionMailer::Base.deliveries.clear }

  it "runs on the mailers queue" do
    expect(described_class.new.queue_name).to eq("mailers")
  end

  it "emails the user a code and stores its digest" do
    described_class.perform_now(user.id)

    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([ [ user.email ] ])
    expect(OneTimeCode.where(user_id: user.id, purpose: "password_reset").count).to eq(1)
  end

  it "does nothing for a missing id (unknown email)" do
    expect { described_class.perform_now(nil) }.not_to raise_error

    expect(ActionMailer::Base.deliveries).to be_empty
    expect(OneTimeCode.count).to eq(0)
  end

  it "does nothing for a user that was deleted" do
    id = user.id
    user.destroy!

    described_class.perform_now(id)

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "is safe to run twice: inside the cooldown the second run sends nothing" do
    2.times { described_class.perform_now(user.id) }

    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(OneTimeCode.where(user_id: user.id).count).to eq(1)
  end

  it "rolls the code back when the mail fails, so the retry can send again" do
    allow(PasswordMailer).to receive(:reset_password_code).and_raise(Net::ReadTimeout)
    expect { described_class.perform_now(user.id) }.to have_enqueued_job(described_class).with(user.id)
    expect(OneTimeCode.count).to eq(0)

    allow(PasswordMailer).to receive(:reset_password_code).and_call_original
    described_class.perform_now(user.id)

    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end
end
