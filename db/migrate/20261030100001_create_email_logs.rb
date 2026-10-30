# A record of each email the app sends (Layer 2, step 5). The body is the text part AS SENT, so it holds the live code or link:
# the owner chose this so an admin can see what was delivered. Read access to this table must be treated like access to the mailbox.
# `recipient` is a plain, lowercase string (not citext) so a trigram index can serve a partial search ("jo@exam").
# There is no foreign key: a row must outlive the user it was sent to. Old rows are removed by `EmailLogs::PurgeJob`.
class CreateEmailLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :email_logs, id: :uuid do |t|
      t.string :recipient, null: false
      t.string :mailer, null: false # "PasswordMailer"
      t.string :action, null: false # "reset_password_code"
      t.string :subject
      t.text :body # text part as sent, cut at 10_000 characters
      t.string :status, null: false # "sent" or "failed"
      t.string :error_class # the class name only, never the message
      t.datetime :sent_at
      t.datetime :created_at, null: false
    end

    add_index :email_logs, :created_at # the purge
    add_index :email_logs, [ :mailer, :action, :created_at ]
    add_index :email_logs, :recipient, using: :gin, opclass: :gin_trgm_ops, name: "index_email_logs_on_recipient_trgm"

    add_check_constraint :email_logs, "status IN ('sent', 'failed')", name: "email_logs_status_values"
    add_check_constraint :email_logs, "char_length(recipient) <= 254", name: "email_logs_recipient_length"
    add_check_constraint :email_logs, "char_length(subject) <= 255", name: "email_logs_subject_length"
    add_check_constraint :email_logs, "char_length(body) <= 10000", name: "email_logs_body_length"
  end
end
