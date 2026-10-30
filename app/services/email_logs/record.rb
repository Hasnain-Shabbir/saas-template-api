module EmailLogs
  class Record
    # Writes one log row for each address the mail went to. The body is the text part of the mail AS SENT, so it holds the live
    # code or link (the owner chose this so an admin can see what was delivered). Treat the table like the mailbox itself.
    # A text over the size limit is cut. `error_class` is the class name of the failure, never its message.
    def self.call(message:, mailer:, action:, status:, error_class: nil)
      body = text_of(message).truncate(ValidationRules::EMAIL_LOG_BODY_MAX_LENGTH, omission: "")
      subject = message.subject.to_s.truncate(ValidationRules::EMAIL_LOG_SUBJECT_MAX_LENGTH, omission: "")
      sent_at = Time.current if status.to_s == "sent"

      Array(message.to).each do |recipient|
        EmailLog.create!(recipient:, mailer:, action:, subject:, body:, status:, error_class:, sent_at:)
      end

      Result.success
    end

    def self.text_of(message)
      (message.text_part || message).body.decoded.to_s
    end
    private_class_method :text_of
  end
end
