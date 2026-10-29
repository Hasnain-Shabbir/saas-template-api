class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::Allowlist

  devise :database_authenticatable, :validatable, :lockable,
         :jwt_authenticatable, jwt_revocation_strategy: self,
         email_regexp: ValidationRules::EMAIL_FORMAT,
         password_length: ValidationRules::PASSWORD_MIN_LENGTH..ValidationRules::PASSWORD_MAX_BYTES

  # Audit log: names of changed fields only. Values are stored just for the fields listed here (none is personal or a secret).
  # `failed_attempts` alone does not make a row (a wrong password would write one each time); the lock itself (`locked_at`) does.
  include Auditable
  audited values: %i[role locked_at terms_version terms_accepted_at], ignore: %i[failed_attempts]

  # The one place roles are defined. A new role is added here and in a migration that changes the
  # `users_role_values` CHECK constraint. Permissions of a role live in the policies, not here.
  enum :role, { super_admin: "super_admin", member: "member" }, default: :member, validate: true

  # Invitations stay (as a record of who was invited) when their inviter is deleted.
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :inviter_id, inverse_of: :inviter, dependent: :nullify

  # The database deletes them with the user (ON DELETE CASCADE), so no callbacks are needed.
  has_many :onboarding_steps, dependent: :delete_all

  # The profile an onboarding step collects. Date of birth and phone are personal data: stored encrypted, so SQL cannot search them.
  # Names stay plain on purpose, so the frontend can search by name later (decision of the owner).
  PROFILE_FIELDS = %i[first_name last_name date_of_birth phone].freeze

  # The address the address onboarding step collects. Plain columns for now (decision of the owner: encrypt later). Line 2 is optional.
  ADDRESS_FIELDS = %i[address_line_1 address_line_2 city state postal_code country].freeze
  ADDRESS_REQUIRED_FIELDS = (ADDRESS_FIELDS - %i[address_line_2]).freeze

  attribute :date_of_birth, :date # the column is text (ciphertext), the model works with a Date
  encrypts :date_of_birth, :phone

  normalizes :email, :pending_email, :previous_email, with: ->(email) { email.strip.downcase }
  normalizes :first_name, :last_name, with: ->(name) { name.squish.presence }
  normalizes :phone, with: ->(phone) { phone.gsub(/[\s-]/, "").presence }
  normalizes :address_line_1, :address_line_2, :city, with: ->(text) { text.squish.presence }
  normalizes :state, :country, with: ->(code) { code.strip.upcase.presence }
  normalizes :postal_code, with: ->(code) { code.strip.presence }

  validates :email, :pending_email, :previous_email, length: { maximum: ValidationRules::EMAIL_MAX_LENGTH }
  validate :password_fits_bcrypt, if: -> { password.present? }
  # A profile field may be empty on the model (a new user has none yet). `Profiles::Update` makes them required.
  validates :first_name, :last_name, length: { maximum: ValidationRules::NAME_MAX_LENGTH }, allow_nil: true
  validates :phone, format: { with: ValidationRules::PHONE_FORMAT, message: Errors::PHONE_INVALID.message }, allow_nil: true
  validate :date_of_birth_is_possible, if: -> { date_of_birth.present? }
  # The same for the address: empty is allowed on the model, `Addresses::Update` makes the fields required.
  validates :address_line_1, :address_line_2, :city, length: { maximum: ValidationRules::ADDRESS_MAX_LENGTH }, allow_nil: true
  validates :state, inclusion: { in: ValidationRules::US_STATE_CODES, message: Errors::STATE_INVALID.message }, allow_nil: true
  validates :postal_code, format: { with: ValidationRules::US_ZIP_FORMAT, message: Errors::POSTAL_CODE_INVALID.message }, allow_nil: true
  validates :country, inclusion: { in: [ ValidationRules::ACCEPTED_COUNTRY ], message: Errors::COUNTRY_UNSUPPORTED.message }, allow_nil: true

  # A new password makes every token issued before it useless.
  after_update :revoke_tokens, if: :saved_change_to_encrypted_password?

  # Devise calls this from a Warden hook on every authenticated request (a JWT request too). That would zero the count of
  # wrong passwords typed into a logged-in operation (requestEmailChange), so a stolen token could guess without a lock.
  # The count is reset on purpose instead: `unlock_access!` in Login, RequestEmailChange, and ResetPassword.
  def reset_failed_attempts! = nil

  def profile_complete? = PROFILE_FIELDS.all? { |field| self[field].present? }

  # True when the user accepted the version of the terms that is current now.
  def terms_accepted? = terms_accepted_at.present? && terms_version == Terms::Current::VERSION

  def address_complete? = ADDRESS_REQUIRED_FIELDS.all? { |field| self[field].present? }

  private

  # The length range counts characters, but bcrypt cuts at bytes (an emoji is 4 bytes).
  def password_fits_bcrypt
    return if password.bytesize <= ValidationRules::PASSWORD_MAX_BYTES

    errors.add(:password, :too_long, count: ValidationRules::PASSWORD_MAX_BYTES)
  end

  def date_of_birth_is_possible
    if date_of_birth > Date.current
      errors.add(:date_of_birth, Errors::DATE_OF_BIRTH_IN_FUTURE.message)
    elsif date_of_birth < ValidationRules::DATE_OF_BIRTH_MAX_AGE_YEARS.years.ago.to_date
      errors.add(:date_of_birth, Errors::DATE_OF_BIRTH_TOO_OLD.message)
    end
  end

  def revoke_tokens
    allowlisted_jwts.delete_all
  end
end
