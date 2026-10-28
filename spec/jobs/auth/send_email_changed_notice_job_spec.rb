require "rails_helper"

RSpec.describe Auth::SendEmailChangedNoticeJob, type: :job do
  include ActiveJob::TestHelper

  let!(:user) { create(:user, previous_email: "old@example.test") }

  before { ActionMailer::Base.deliveries.clear }

  it "runs on the mailers queue" do
    expect(described_class.new.queue_name).to eq("mailers")
  end

  it "emails the old address, then forgets it" do
    described_class.perform_now(user.id)

    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([ [ "old@example.test" ] ])
    expect(user.reload.previous_email).to be_nil
  end

  it "is safe to run twice: the second run sends nothing" do
    2.times { described_class.perform_now(user.id) }

    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end

  it "does nothing for a missing id, or a user that was deleted" do
    id = user.id
    user.destroy!

    expect { described_class.perform_now(id) }.not_to raise_error
    expect { described_class.perform_now(nil) }.not_to raise_error
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "keeps the old address when the mail fails, so the retry can send it" do
    allow(EmailChangeMailer).to receive(:changed_notice).and_raise(Net::ReadTimeout)
    expect { described_class.perform_now(user.id) }.to have_enqueued_job(described_class).with(user.id)
    expect(user.reload.previous_email).to eq("old@example.test")

    allow(EmailChangeMailer).to receive(:changed_notice).and_call_original
    described_class.perform_now(user.id)

    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end
end
