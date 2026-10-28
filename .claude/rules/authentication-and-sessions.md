---
paths:
  - "app/graphql/concerns/authenticatable.rb"
  - "app/graphql/mutations/login.rb"
  - "app/graphql/mutations/logout.rb"
  - "app/graphql/mutations/request_password_reset.rb"
  - "app/graphql/mutations/reset_password.rb"
  - "app/controllers/graphql_controller.rb"
  - "app/models/user.rb"
  - "app/models/one_time_code.rb"
  - "app/services/auth/*_one_time_code.rb"
  - "app/services/auth/reset_password.rb"
  - "app/models/allowlisted_jwt.rb"
  - "config/initializers/devise.rb"
---

# Authentication and sessions (security critical)

- **Never** call `JWT.decode` with verification off (`JWT.decode(token, key, false)`) anywhere. Never trust a token's payload before the signature and expiry are verified. Verification belongs to the library (devise-jwt and Warden), not to hand-written decoding.
- Tokens are revocable: an allowlist row per token, deleted on logout. Password change, password reset, archive, and access revoke delete the user's allowlisted tokens.
- Token expiry is set in one place in the devise-jwt config. Do not lengthen it without asking.
- Login failure, unknown email, and locked account return **one** message and code (`INVALID_CREDENTIALS`). Reset requests always report success. Never reveal whether an email has an account, in the message, the status, or (as far as possible) the timing.
- Lock after 5 failed attempts for 1 hour (Devise lockable). A reset unlocks the account (documented decision).
- Password reset uses a 6-digit email OTP (`OneTimeCode`), not a link. The code is single use, expires in 10 minutes, and is stored only as a keyed HMAC digest. 5 wrong guesses delete it (counted per code, not per IP). A new request replaces the old code, with a 60 second resend cooldown that still answers success. A weak password does not use the code up. The limits are constants on `OneTimeCode`, the format is in `ValidationRules`. Do not loosen them without asking.
- The code is made inside the job (arguments are the user id only). It never goes in a subject, a log, or a job argument. Passwords never appear in logs or job arguments.
- Anonymous operations are throttled in `config/initializers/rack_attack.rb` (per IP, one public operation per request). Do not weaken it. Every login failure path (unknown, wrong password, locked) runs bcrypt once, so timing does not leak.
- Secrets (the devise-jwt secret) live in credentials. Never print or copy them (see `no-env-access.md`).

## Required negative tests (keep them passing)
Garbage token, expired token, token after logout, token after password change, wrong password, unknown email, locked account, reused, expired, wrong, or exhausted (5 guesses) reset code.

## Process
Any change in these files needs a security read-through before it is called done: forged input, replay, enumeration, and what is logged.
