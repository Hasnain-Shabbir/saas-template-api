# An offer to create an account. Only a digest of the token is stored; the token itself exists only in the email.
class Invitation < ApplicationRecord
  LIFETIME = 7.days
  RESEND_AFTER = 60.seconds

  belongs_to :inviter, class_name: "User", optional: true, inverse_of: :sent_invitations

  # Same roles as users (one place to define them). A new role also needs a migration for `invitations_role_values`.
  enum :role, User.roles, validate: true

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, length: { maximum: ValidationRules::EMAIL_MAX_LENGTH },
                    format: { with: ValidationRules::EMAIL_FORMAT, allow_blank: true }
  validates :expires_at, presence: true

  scope :open, -> { where(accepted_at: nil, revoked_at: nil) }
  scope :revoked, -> { where(accepted_at: nil).where.not(revoked_at: nil) }

  # A keyed HMAC, never a plain hash. The token is already 256 random bits; the key means a leaked table
  # cannot be used to check guesses or to rebuild a link.
  def self.digest(token)
    OpenSSL::HMAC.hexdigest("SHA256", digest_key, token.to_s)
  end

  def self.digest_key
    @digest_key ||= Rails.application.key_generator.generate_key("invitation-token")
  end
  private_class_method :digest_key

  def self.generate_token = SecureRandom.urlsafe_base64(ValidationRules::INVITATION_TOKEN_BYTES)

  def open? = accepted_at.nil? && revoked_at.nil?

  def expired? = expires_at <= Time.current

  def usable? = open? && !expired?

  def recently_sent? = last_sent_at.present? && last_sent_at > RESEND_AFTER.ago
end
