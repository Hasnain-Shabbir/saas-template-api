# One row per email the app tried to send: to whom, which mailer and action, the subject, the result, and the body as sent.
# The body holds live codes and links (owner's decision), so whoever reads this table can use them until they expire.
# Written by `EmailLogs::Record`, never by hand. Removed by `EmailLogs::PurgeJob` after RETENTION.
class EmailLog < ApplicationRecord
  RETENTION = 6.years # counted from created_at

  enum :status, { sent: "sent", failed: "failed" }, validate: true

  normalizes :recipient, with: ->(value) { value.to_s.strip.downcase }

  validates :recipient, :mailer, :action, presence: true
  validates :recipient, length: { maximum: ValidationRules::EMAIL_MAX_LENGTH }
  validates :subject, length: { maximum: ValidationRules::EMAIL_LOG_SUBJECT_MAX_LENGTH }
  validates :body, length: { maximum: ValidationRules::EMAIL_LOG_BODY_MAX_LENGTH }

  scope :expired, -> { where(created_at: ...RETENTION.ago) }

  # Partial, case-insensitive search by address ("jo@exam"). The `%` and `_` the caller typed are matched literally.
  scope :recipient_matching, ->(part) { where("recipient LIKE ?", "%#{sanitize_sql_like(part.to_s.strip.downcase)}%") }
end
