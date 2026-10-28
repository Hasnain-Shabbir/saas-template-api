require "rails_helper"

RSpec.describe PasswordMailer, type: :mailer do
  let(:user) { build(:user, email: "person@example.test") }
  let(:mail) { described_class.reset_password_code(user, "042917") }

  it "goes to the user from the configured sender" do
    expect(mail.to).to eq([ "person@example.test" ])
    expect(mail.from).to eq([ Rails.configuration.x.mailer_from ])
  end

  it "shows the code in the text and the html part, but not in the subject" do
    expect(mail.text_part.body.decoded).to include("042917")
    expect(mail.html_part.body.decoded).to include("042917")
    expect(mail.subject).to eq(PasswordMailer::SUBJECT)
    expect(mail.subject).not_to include("042917")
  end

  it "says how long the code lives, from the model setting" do
    expect(mail.text_part.body.decoded).to include("expires in #{OneTimeCode::LIFETIME.inspect}")
  end

  it "does not contain a link, the password, or its hash" do
    body = mail.text_part.body.decoded + mail.html_part.body.decoded

    expect(body).not_to include("http://", "https://", "encrypted_password", "correct horse battery")
  end
end
