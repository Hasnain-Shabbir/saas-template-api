# The single home of input rules (formats and limits). Models, services, and specs read from here.
# Never write a regexp or a length limit for user input anywhere else.
module ValidationRules
  # ASCII only on purpose: look-alike (Cyrillic) and zero-width characters cannot make a second "identical" account.
  EMAIL_FORMAT = /\A[a-z0-9._%+-]+@(?:[a-z0-9-]+\.)+[a-z]{2,}\z/i
  EMAIL_MAX_LENGTH = 254 # RFC 5321

  # PostgreSQL cannot store a NUL byte in text. Refused for the whole request, so no string argument can reach the database with one.
  NULL_BYTE = /\\u0000|\x00/i

  PASSWORD_MIN_LENGTH = 10
  PASSWORD_MAX_BYTES = 72 # bcrypt ignores everything after 72 bytes, so a longer password would be a lie

  OTP_LENGTH = 6 # digits
  OTP_FORMAT = /\A\d{#{OTP_LENGTH}}\z/

  NAME_MAX_LENGTH = 100 # first name and last name
  # International format only: "+", then 8 to 15 digits, the first not 0 (E.164). Spaces and dashes are removed before the check.
  PHONE_FORMAT = /\A\+[1-9]\d{7,14}\z/
  DATE_OF_BIRTH_MAX_AGE_YEARS = 120

  ADDRESS_MAX_LENGTH = 100 # address line 1, address line 2 and city
  POSTAL_CODE_MAX_LENGTH = 10 # "12345-6789"
  # Only the United States is accepted for now. A new country is a new rule here, with its own state and postal code format.
  ACCEPTED_COUNTRY = "US"
  US_ZIP_FORMAT = /\A\d{5}(?:-\d{4})?\z/ # 12345 or 12345-6789
  # The 50 states and the District of Columbia. Territories (PR, GU, ...) are not accepted until the owner decides.
  US_STATE_CODES = %w[
    AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT
    NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY
  ].freeze

  TERMS_VERSION_MAX_LENGTH = 20

  # The key of an onboarding step: a short snake_case name, set in `Onboarding::Registry`.
  ONBOARDING_STEP_KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/
  ONBOARDING_STEP_KEY_MAX_LENGTH = 50

  # The invitation token: random bytes, written URL-safe (base64 without padding: 4 characters per 3 bytes, rounded up).
  INVITATION_TOKEN_BYTES = 32
  INVITATION_TOKEN_FORMAT = /\A[A-Za-z0-9_-]{#{(INVITATION_TOKEN_BYTES * 4 / 3.0).ceil}}\z/
end
