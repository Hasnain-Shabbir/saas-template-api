require "rails_helper"

RSpec.describe Invitations::SendInvitationJob, type: :job do
  include ActiveJob::TestHelper

  let!(:invitation) { create(:invitation, email: "invitee@example.test") }

  before { ActionMailer::Base.deliveries.clear }

  it "runs on the mailers queue" do
    expect(described_class.new.queue_name).to eq("mailers")
  end

  it "emails the link and stores only the digest of the token" do
    described_class.perform_now(invitation.id)

    mail = ActionMailer::Base.deliveries.last
    token = mail.text_part.body.decoded[/token=([\w-]+)/, 1]
    expect(mail.to).to eq([ "invitee@example.test" ])
    expect(token).to match(ValidationRules::INVITATION_TOKEN_FORMAT)
    expect(invitation.reload.token_digest).to eq(Invitation.digest(token))
    expect(invitation.attributes.values.map(&:to_s)).not_to include(token)
  end

  it "does nothing for a missing id (an email that has an account) or a deleted invitation" do
    id = invitation.id
    invitation.destroy!

    expect { described_class.perform_now(id) }.not_to raise_error
    expect { described_class.perform_now(nil) }.not_to raise_error
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "does nothing for a used or revoked invitation" do
    invitation.update!(revoked_at: Time.current)

    described_class.perform_now(invitation.id)

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "is safe to run twice: inside the cooldown the second run sends nothing" do
    2.times { described_class.perform_now(invitation.id) }

    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end

  it "rolls the token back when the mail fails, so the retry can send again" do
    allow(InvitationMailer).to receive(:invite).and_raise(Net::ReadTimeout)
    expect { described_class.perform_now(invitation.id) }.to have_enqueued_job(described_class).with(invitation.id)
    expect(invitation.reload.token_digest).to be_nil
    expect(invitation.last_sent_at).to be_nil

    allow(InvitationMailer).to receive(:invite).and_call_original
    described_class.perform_now(invitation.id)

    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end
end
