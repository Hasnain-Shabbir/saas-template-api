# Logs every mail a mailer delivers (see `EmailLog`), whether it was sent or failed. Included by `ApplicationMailer` and `DeviseMailer`.
# A failure is logged and then raised again, so the job still retries.
module EmailLoggable
  extend ActiveSupport::Concern

  included do
    around_deliver :log_delivery
  end

  private

  def log_delivery
    yield
  rescue StandardError => error
    record_email_log(:failed, error_class: error.class.name)
    raise
  else
    record_email_log(:sent)
  end

  # A broken log must never stop an email (a password reset code): the error is reported and the mail goes on.
  def record_email_log(status, error_class: nil)
    Rails.error.handle do
      EmailLogs::Record.call(message:, mailer: self.class.name, action: action_name, status:, error_class:)
    end
  end
end
