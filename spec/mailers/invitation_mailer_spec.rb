require "rails_helper"

RSpec.describe InvitationMailer, type: :mailer do
  let(:invitation) { build(:invitation, email: "invitee@example.test") }
  let(:token) { "A" * 43 }
  let(:mail) { described_class.invite(invitation, token) }
  let(:link) { "#{Rails.configuration.x.frontend_url}/accept-invitation?token=#{token}" }

  it "goes to the invited address from the configured sender" do
    expect(mail.to).to eq([ "invitee@example.test" ])
    expect(mail.from).to eq([ Rails.configuration.x.mailer_from ])
  end

  it "has the link in the text and the html part, but not in the subject" do
    expect(mail.text_part.body.decoded).to include(link)
    expect(mail.html_part.body.decoded).to include(link)
    expect(mail.subject).to eq(described_class::SUBJECT)
    expect(mail.subject).not_to include(token)
  end

  it "says how long the link lives, from the model setting" do
    expect(mail.text_part.body.decoded).to include("expires in #{Invitation::LIFETIME.inspect}")
  end

  it "does not contain a password, the role, or the inviter" do
    invitation.inviter = build(:user, email: "boss@example.test")
    invitation.role = "super_admin"
    body = mail.text_part.body.decoded + mail.html_part.body.decoded

    expect(body).not_to include("boss@example.test", "super_admin", "invitee@example.test")
  end
end
