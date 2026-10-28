class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::Allowlist

  devise :database_authenticatable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: self

  normalizes :email, with: ->(email) { email.strip.downcase }

  # A new password makes every token issued before it useless.
  after_update :revoke_tokens, if: :saved_change_to_encrypted_password?

  private

  def revoke_tokens
    allowlisted_jwts.delete_all
  end
end
