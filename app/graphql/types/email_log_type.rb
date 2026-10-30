module Types
  class EmailLogType < Types::BaseObject
    description "A record of one email the app sent, or tried to send. Only a super_admin can read it"

    field :id, ID, null: false, description: "Unique id of the log entry"
    field :recipient, String, null: false, description: "The address the mail was sent to, in lower case"
    field :mailer, String, null: false, description: "The mailer that built the mail, for example PasswordMailer"
    field :action, String, null: false, description: "The mailer action, for example reset_password_code"
    field :subject, String, null: true, description: "The subject line"
    # The body holds the live code or link as it was sent. Each read is written to the read audit log (group email_body).
    # Keep the word "audit" out of the descriptions: audit_spec checks that the schema says nothing about the audit log.
    field :body, String, null: true, sensitive: :email_body, description: "The text of the mail as it was sent, with any code or link in it. Each read is recorded with the reader"
    field :status, Types::EmailLogStatusEnum, null: false, description: "Whether the mail was sent or failed"
    field :sent_at, GraphQL::Types::ISO8601DateTime, null: true, description: "When the mail was sent. Empty when it failed"
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false, description: "When the log entry was written"
  end
end
