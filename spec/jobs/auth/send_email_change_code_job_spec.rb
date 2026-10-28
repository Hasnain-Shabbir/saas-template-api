require "rails_helper"

RSpec.describe Auth::SendEmailChangeCodeJob, type: :job do
  include ActiveJob::TestHelper

  let!(:user) { create(:user, pending_email: "fresh@example.test") }

  before { ActionMailer::Base.deliveries.clear }

  it "runs on the mailers queue" do
    expect(described_class.new.queue_name).to eq("mailers")
  end

  it "emails the pending address a code and stores its digest" do
    described_class.perform_now(user.id)

    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([ [ "fresh@example.test" ] ])
    expect(OneTimeCode.where(user_id: user.id, purpose: "email_change").count).to eq(1)
  end

  it "does nothing without a pending email (a taken address)" do
    user.update!(pending_email: nil)

    described_class.perform_now(user.id)

    expect(ActionMailer::Base.deliveries).to be_empty
    expect(OneTimeCode.count).to eq(0)
  end

  it "does nothing for a missing id, or a user that was deleted" do
    id = user.id
    user.destroy!

    expect { described_class.perform_now(id) }.not_to raise_error
    expect { described_class.perform_now(nil) }.not_to raise_error
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "is safe to run twice: inside the cooldown the second run sends nothing" do
    2.times { described_class.perform_now(user.id) }

    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(OneTimeCode.where(user_id: user.id).count).to eq(1)
  end

  it "rolls the code back when the mail fails, so the retry can send again" do
    allow(EmailChangeMailer).to receive(:change_code).and_raise(Net::ReadTimeout)
    expect { described_class.perform_now(user.id) }.to have_enqueued_job(described_class).with(user.id)
    expect(OneTimeCode.count).to eq(0)

    allow(EmailChangeMailer).to receive(:change_code).and_call_original
    described_class.perform_now(user.id)

    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end
end
