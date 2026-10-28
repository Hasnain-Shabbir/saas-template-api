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
end
