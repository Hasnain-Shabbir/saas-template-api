# A short code sent to a user (by email) to prove they control the mailbox. Only a digest is stored.
class OneTimeCode < ApplicationRecord
  LIFETIME = 10.minutes
  MAX_ATTEMPTS = 5 # wrong guesses, then the code is deleted
  RESEND_AFTER = 60.seconds

  belongs_to :user

  enum :purpose, { password_reset: "password_reset" }, validate: true

  validates :code_digest, :expires_at, presence: true

  # A keyed HMAC, never a plain hash: a 6-digit code has only a million values, so an unkeyed hash is undone in a moment.
  # The user and the purpose are part of the input, so the same digits give a different digest for each user.
  def self.digest(user_id:, purpose:, code:)
    OpenSSL::HMAC.hexdigest("SHA256", digest_key, "#{user_id}:#{purpose}:#{code}")
  end

  def self.digest_key
    @digest_key ||= Rails.application.key_generator.generate_key("one-time-code")
  end
  private_class_method :digest_key

  def expired?
    expires_at <= Time.current
  end

  def recently_sent?
    created_at > RESEND_AFTER.ago
  end

  def matches?(digest)
    ActiveSupport::SecurityUtils.secure_compare(code_digest, digest)
  end
end
