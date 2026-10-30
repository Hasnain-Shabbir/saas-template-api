require "rails_helper"

RSpec.describe DeviseMailer, type: :mailer do
  # Devise's own templates need routes this API does not have, so the test uses a mail with an inline body.
  let(:mailer_class) do
    Class.new(described_class) do
      def hello
        mail(from: Rails.configuration.x.mailer_from, to: "person@example.test", subject: "Hello", body: "Unlock code 042917")
      end
    end
  end

  before { stub_const("DeviseHelloMailer", mailer_class) }

  it "is the mailer Devise uses" do
    expect(Devise.mailer).to eq(described_class)
    expect(described_class.ancestors).to include(EmailLoggable)
  end

  it "logs a mail it delivers" do
    DeviseHelloMailer.hello.deliver_now

    expect(EmailLog.last).to have_attributes(recipient: "person@example.test", mailer: "DeviseHelloMailer", action: "hello",
                                             status: "sent", body: "Unlock code 042917")
  end
end
