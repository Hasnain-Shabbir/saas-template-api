require "rails_helper"

RSpec.describe EmailChangeMailer, type: :mailer do
  let(:user) { build(:user, email: "person@example.test", pending_email: "fresh@example.test", previous_email: "old@example.test") }

  describe "#change_code" do
    let(:mail) { described_class.change_code(user, "042917") }

    it "goes to the pending address from the configured sender" do
      expect(mail.to).to eq([ "fresh@example.test" ])
      expect(mail.from).to eq([ Rails.configuration.x.mailer_from ])
    end

    it "shows the code in the text and the html part, but not in the subject" do
      expect(mail.text_part.body.decoded).to include("042917")
      expect(mail.html_part.body.decoded).to include("042917")
      expect(mail.subject).to eq(described_class::CODE_SUBJECT)
      expect(mail.subject).not_to include("042917")
    end

    it "says how long the code lives, from the model setting" do
      expect(mail.text_part.body.decoded).to include("expires in #{OneTimeCode::LIFETIME.inspect}")
    end

    it "does not contain a link, a password, or another address" do
      body = mail.text_part.body.decoded + mail.html_part.body.decoded

      expect(body).not_to include("http://", "https://", "encrypted_password", "correct horse battery", "person@example.test", "old@example.test")
    end
  end

  describe "#changed_notice" do
    let(:mail) { described_class.changed_notice(user) }

    it "goes to the previous address" do
      expect(mail.to).to eq([ "old@example.test" ])
      expect(mail.subject).to eq(described_class::NOTICE_SUBJECT)
    end

    it "has a text and an html part, with no code, link, or address" do
      body = mail.text_part.body.decoded + mail.html_part.body.decoded

      expect(mail.text_part).to be_present
      expect(mail.html_part).to be_present
      expect(body).not_to match(/\d{6}/)
      expect(body).not_to include("http://", "https://", "person@example.test", "fresh@example.test", "old@example.test")
    end
  end
end
