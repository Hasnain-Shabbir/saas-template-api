class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::Allowlist

  devise :database_authenticatable, :validatable, :lockable,
         :jwt_authenticatable, jwt_revocation_strategy: self,
         email_regexp: ValidationRules::EMAIL_FORMAT,
         password_length: ValidationRules::PASSWORD_MIN_LENGTH..ValidationRules::PASSWORD_MAX_BYTES

  # The one place roles are defined. A new role is added here and in a migration that changes the
  # `users_role_values` CHECK constraint. Permissions of a role live in the policies, not here.
  enum :role, { super_admin: "super_admin", member: "member" }, default: :member, validate: true

  # Invitations stay (as a record of who was invited) when their inviter is deleted.
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :inviter_id, inverse_of: :inviter, dependent: :nullify

  normalizes :email, :pending_email, :previous_email, with: ->(email) { email.strip.downcase }

  validates :email, :pending_email, :previous_email, length: { maximum: ValidationRules::EMAIL_MAX_LENGTH }
  validate :password_fits_bcrypt, if: -> { password.present? }

  # A new password makes every token issued before it useless.
  after_update :revoke_tokens, if: :saved_change_to_encrypted_password?

  # Devise calls this from a Warden hook on every authenticated request (a JWT request too). That would zero the count of
  # wrong passwords typed into a logged-in operation (requestEmailChange), so a stolen token could guess without a lock.
  # The count is reset on purpose instead: `unlock_access!` in Login, RequestEmailChange, and ResetPassword.
  def reset_failed_attempts! = nil

  private

  # The length range counts characters, but bcrypt cuts at bytes (an emoji is 4 bytes).
  def password_fits_bcrypt
    return if password.bytesize <= ValidationRules::PASSWORD_MAX_BYTES

    errors.add(:password, :too_long, count: ValidationRules::PASSWORD_MAX_BYTES)
  end

  def revoke_tokens
    allowlisted_jwts.delete_all
  end
end
