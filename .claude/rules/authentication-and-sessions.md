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
  - "app/services/auth/login.rb"
  - "app/services/auth/verify_login.rb"
  - "app/models/allowlisted_jwt.rb"
  - "config/initializers/devise.rb"
---

# Authentication and sessions (security critical)

- **Never** call `JWT.decode` with verification off (`JWT.decode(token, key, false)`) anywhere. Never trust a token's payload before the signature and expiry are verified. Verification belongs to the library (devise-jwt and Warden), not to hand-written decoding.
- Tokens are revocable: an allowlist row per token, deleted on logout. Password change, password reset, archive, and access revoke delete the user's allowlisted tokens.
- Token expiry is set in one place in the devise-jwt config. Do not lengthen it without asking.
- Login failure, unknown email, and locked account return **one** message and code (`INVALID_CREDENTIALS`). Reset requests always report success. Never reveal whether an email has an account, in the message, the status, or (as far as possible) the timing.
- **Archived users (owner decision):** login step 1 answers `ACCOUNT_ARCHIVED` ("Your access has been blocked...") instead of `INVALID_CREDENTIALS`, **only when the password is right**, so the user can ask an administrator and an outsider still learns nothing. A wrong password for an archived account gives `INVALID_CREDENTIALS`. Step 2 (`INVALID_CODE`), password reset (silent success, no mail) and every token give nothing. Archive deletes tokens and pending codes (`Users::Archive`).
- Lock after 5 failed attempts for 1 hour (Devise lockable). A reset unlocks the account (documented decision).
- **Login has two steps, for every user.** `login(email, password)` checks the password and, when it is right, queues an email with a 6-digit code (`SendLoginCodeJob`, purpose `login`). It returns `success` and **no token**. `verifyLoginCode(email, code)` checks the code and only then issues the token. The code works once and uses the same limits as the reset code (10 minutes, 5 wrong guesses, 60 second resend cooldown, keyed HMAC digest). Both operations are public and throttled.
- What step 1 and step 2 reveal: step 1 gives `INVALID_CREDENTIALS` for an unknown email, a wrong password, and a locked account (bcrypt runs once). Step 2 gives one `INVALID_CODE` for every failure (unknown email, no code, wrong, expired, used up, bad format, locked or archived account). A correct password in step 1 is the only difference an outsider can see, and only a caller who knows the password sees it.
- **Lockout counts used-up login codes, not each wrong guess.** A code that reaches 5 wrong guesses counts as one failed login (the same Devise counter), so 5 used-up codes lock the account. Counting each guess would let anyone who knows an email lock that account, because step 2 needs no password. The counter is reset only when a code is verified, **never at step 1** (otherwise a password holder could reset it by asking for a new code). Do not move the reset.
- There is no test-only OTP bypass and no fixed code anywhere in the app. Specs read the code from the delivered mail. The attack run issues a code into the test database (`otp_helper.rb`). Never add a switch that makes the code predictable.
- Password reset uses a 6-digit email OTP (`OneTimeCode`), not a link. The code is single use, expires in 10 minutes, and is stored only as a keyed HMAC digest. 5 wrong guesses delete it (counted per code, not per IP). A new request replaces the old code, with a 60 second resend cooldown that still answers success. A weak password does not use the code up. The limits are constants on `OneTimeCode`, the format is in `ValidationRules`. Do not loosen them without asking.
- The code is made inside the job (arguments are the user id only). It never goes in a subject, a log, or a job argument. Passwords never appear in logs or job arguments.
- Anonymous operations are throttled in `config/initializers/rack_attack.rb` (per IP, one public operation per request). Do not weaken it. Every login failure path (unknown, wrong password, locked) runs bcrypt once, so timing does not leak.
- Secrets (the devise-jwt secret) live in credentials. Never print or copy them (see `no-env-access.md`).

## Required negative tests (keep them passing)
Garbage token, expired token, token after logout, token after password change, wrong password, unknown email, locked account, reused, expired, wrong, or exhausted (5 guesses) reset code. The same for the login code, plus: no token at step 1, a code of another user or purpose, an account locked between the two steps.

## Process
Any change in these files needs a security read-through before it is called done: forged input, replay, enumeration, and what is logged.
