require "rails_helper"

# Every mailer must leave a log row with the mail as it was sent. A new mailer is added to `mails` below.
RSpec.describe ApplicationMailer, type: :mailer do
  let(:user) { create(:user, email: "person@example.test", pending_email: "new@example.test", previous_email: "old@example.test") }
  let(:invitation) { create(:invitation, email: "invitee@example.test") }
  let(:code) { "042917" }
  let(:token) { SecureRandom.urlsafe_base64(ValidationRules::INVITATION_TOKEN_BYTES) }

  let(:mails) do
    {
      "PasswordMailer#reset_password_code" => -> { PasswordMailer.reset_password_code(user, code) },
      "EmailChangeMailer#change_code" => -> { EmailChangeMailer.change_code(user, code) },
      "EmailChangeMailer#changed_notice" => -> { EmailChangeMailer.changed_notice(user) },
      "InvitationMailer#invite" => -> { InvitationMailer.invite(invitation, token) }
    }
  end

  it "logs every mailer as sent" do
    mails.each_value { |build_mail| build_mail.call.deliver_now }

    logs = EmailLog.all.to_a
    expect(logs.map { |log| "#{log.mailer}##{log.action}" }).to match_array(mails.keys)
    expect(logs).to all(have_attributes(status: "sent", error_class: nil))
  end

  it "stores the mail as it was delivered, with the code or the link" do
    PasswordMailer.reset_password_code(user, code).deliver_now
    InvitationMailer.invite(invitation, token).deliver_now

    expect(EmailLog.find_by(action: "reset_password_code").body).to include(code)
    expect(EmailLog.find_by(action: "invite").body).to include("token=#{ERB::Util.url_encode(token)}")
  end

  it "stores the address the mail went to" do
    PasswordMailer.reset_password_code(user, code).deliver_now

    expect(EmailLog.last).to have_attributes(recipient: "person@example.test", subject: PasswordMailer::SUBJECT)
  end

  it "logs a failed delivery with the error class only, and still raises so the job retries" do
    allow_any_instance_of(Mail::Message).to receive(:deliver).and_raise(Net::ReadTimeout, "secret detail")

    expect { PasswordMailer.reset_password_code(user, code).deliver_now }.to raise_error(Net::ReadTimeout)

    log = EmailLog.last
    expect(log).to have_attributes(status: "failed", error_class: "Net::ReadTimeout", sent_at: nil)
    expect(log.attributes.values.join(" ")).not_to include("secret detail")
  end

  it "does not stop the email when the log cannot be written" do
    allow(EmailLogs::Record).to receive(:call).and_raise(ActiveRecord::StatementInvalid)
    allow(Rails.error).to receive(:report)

    expect { PasswordMailer.reset_password_code(user, code).deliver_now }.not_to raise_error
    expect(ActionMailer::Base.deliveries.last.to).to eq([ "person@example.test" ])
    expect(Rails.error).to have_received(:report)
  end
end
