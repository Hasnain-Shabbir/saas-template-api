require "rails_helper"

RSpec.describe EmailLogs::Record do
  include ActiveSupport::Testing::TimeHelpers

  let(:message) do
    Mail.new do
      to "person@example.test"
      subject "Your password reset code"
      text_part { body "Your code is:\n\n042917\n\nOpen https://app.example.test/x?token=live-token" }
      html_part { body "<p>042917</p>" }
    end
  end

  def record(status: :sent, error_class: nil, message: self.message)
    described_class.call(message:, mailer: "PasswordMailer", action: "reset_password_code", status:, error_class:)
  end

  it "stores who, which mailer and action, the subject, the status and the time" do
    freeze_time do
      record
      log = EmailLog.last

      expect(log).to have_attributes(recipient: "person@example.test", mailer: "PasswordMailer", action: "reset_password_code",
                                     subject: "Your password reset code", status: "sent", error_class: nil, sent_at: Time.current)
    end
  end

  it "stores the text part as sent, with the code and the link" do
    record

    expect(EmailLog.last.body).to eq("Your code is:\n\n042917\n\nOpen https://app.example.test/x?token=live-token")
  end

  it "stores a failure with the error class only and no sent_at" do
    record(status: :failed, error_class: "Net::ReadTimeout")

    expect(EmailLog.last).to have_attributes(status: "failed", error_class: "Net::ReadTimeout", sent_at: nil)
  end

  it "writes one row for each address" do
    message.to = [ "a@example.test", "b@example.test" ]

    expect { record }.to change(EmailLog, :count).by(2)
    expect(EmailLog.pluck(:recipient)).to contain_exactly("a@example.test", "b@example.test")
  end

  it "cuts a body over the limit instead of failing" do
    message.text_part.body = "x" * (ValidationRules::EMAIL_LOG_BODY_MAX_LENGTH + 500)

    expect { record }.to change(EmailLog, :count).by(1)
    expect(EmailLog.last.body.length).to eq(ValidationRules::EMAIL_LOG_BODY_MAX_LENGTH)
  end

  it "reads the body of a mail that has no parts" do
    plain = Mail.new(to: "person@example.test", subject: "Hello", body: "Code 042917")

    record(message: plain)

    expect(EmailLog.last.body).to eq("Code 042917")
  end
end
