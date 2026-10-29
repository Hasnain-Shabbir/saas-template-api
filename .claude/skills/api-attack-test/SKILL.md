---
name: api-attack-test
description: Hard black-box security and QA attack run against the local GraphQL API before a push. Starts test-mode and production-mode servers on the test database, attacks every operation (auth, forged tokens, injection, abuse, rate limits, headers, logs), and reports findings. Use after adding or changing an operation, auth, limits, or config, and before pushing.
---

# API attack test

Act as a hostile security tester and a QA engineer. The goal is to break the API locally, before anyone else does.

## Safety (read first)
- **Local only, test database only.** `run.sh` refuses to start if the database name does not end in `_test`. Never point it at a real system.
- Never read secrets (`no-env-access.md`). The production-mode key is random and thrown away by the script.
- Do not change application code while attacking. Report first, fix after the owner agrees (`working-agreement.md`).

## Run
```
.claude/skills/api-attack-test/scripts/run.sh          # output in tmp/attack-test/ (ignored by git)
```
Both servers run with `ALLOW_PUBLIC_SIGN_UP=true` (the template default is off), because the script makes its users with `signUp`. Every user the script makes is onboarded at once (profile, address and terms saved: the server finishes the steps) because members are blocked from everything else until then; sections N and P make users with `onboard: false` to test that. The production-mode server gets random throwaway Active Record Encryption keys from environment variables. The default-off answer (FORBIDDEN) is covered by a spec, not by this run. `otp_helper.rb` also promotes a user to super_admin and mints invitations (test database only).
It starts two servers (test mode on 4001, production mode on 4002), runs `scripts/attack.rb` against both, checks the production log for leaked credentials, stops the servers, and empties the test database. Takes about 3 to 4 minutes.
Baseline first: `bundle exec rspec`, `bin/rubocop`, `bin/brakeman -q`.

## What it covers
| Section | Attacks |
|---|---|
| A | Functional regression: signup, login, logout, duplicates, case and spaces, password rules |
| B | Token attacks: `alg=none`, wrong secret, expired, tampered payload, flipped signature, garbage, wrong scheme |
| C | Input fuzzing: SQL injection (also blind `pg_sleep` timing and second-order LIKE patterns), header injection, XSS and template payloads (the reset email body is check I24), look-alike characters, oversized bodies, extra fields |
| D | GraphQL abuse: introspection, suggestions, alias batching, fragment cycles, directive floods, complexity, malformed variables and bodies, wrong content types |
| E | Timing: known vs unknown email |
| F | CORS, debug routes, headers, HSTS, Host header |
| G | Concurrency: parallel signups, logins, logouts |
| H | Lockout and rate limiting (production mode) |
| I | Password reset (email code): enumeration, guess limit, replay, expiry, races, reset email body |
| J | OWASP GraphQL cheat sheet: array batching (J1), NoSQL objects and shell metacharacters (J2), guessed field names and `node`/`nodes` (J3), leaks in error messages (J4), query cost and timeout (J5) |
| Z | **Schema-driven**: reads the schema, then for every query and mutation tries no token, a garbage token, and nine nasty string values, and checks for 500s. New operations are covered automatically. It also has probes that stay dormant (INFO) until the schema has something to test: depth limit (Z5), huge `first`/`limit` and unbounded lists (Z6), IDOR with another user's id (Z7), SSRF with a local canary listener (Z8). |
| M | Invitations: no token and garbage token (M1), member denied and role escalation (M2), hostile tokens (M3), mass assignment (M4), same answer for new and existing email (M5), alias batching (M6); test mode with a minted token: accept, replay, role from the invitation, expired, revoked, weak password, email taken meanwhile, parallel accepts, no privilege after accept (M7 to M16), resend reopens a revoked invitation but never a used one (M18, M19); prod mode: 30 per hour per IP (M17) |
| N | Onboarding: no token, garbage token and bad input as nobody (N1), response shows only the allowed fields (N2), a client cannot mark a step done because `completeOnboardingStep` does not exist (N3), hostile and empty terms versions (N4), mass assignment of `userId`, `role`, `termsAcceptedAt` (N5), alias batching (N6), token after logout (N7); the gate behind aliases and fragments (N8), no step finished out of order (N10, needs two steps), same data twice (N11), parallel saves (N12), and the gate opening for one user while another stays blocked (N13). With an empty registry nobody is blocked and the gate checks are INFO. |
| P | Profile: UNAUTHENTICATED before validation (P1), empty profile (P2), wrong phone and date of birth (P3), hostile and empty names, 100 vs 101 characters (P4), mass assignment of `userId`, `id`, `email`, `role` (P5), save and read back through `me` (P6), same data again (P7), isolation between users (P8), parallel saves (P9), date of birth and phone stored as ciphertext (P10, test mode), the server finishes the profile step (P11) |
| Q | Address: UNAUTHENTICATED before validation (Q1), empty address (Q2), wrong state, ZIP code and country, only US accepted (Q3), hostile and empty text, 100 vs 101 characters (Q4), mass assignment (Q5), save and read back (Q6), same data again (Q7), optional line 2 (Q7a), isolation between users (Q8), parallel saves (Q9), the server finishes the address step in order (Q10) |
| R | Terms: empty at first (R1), a wrong version is refused and nothing is recorded (R2), the current version is recorded with the server time (R3), accepting again keeps the first time (R4), the server finishes the terms step after the earlier steps (R5) |
| AUD | Audit log (test mode, runs last): rows exist (AUD1), no password, bcrypt digest, JWT, email address, profile or address value in any row (AUD2), every row has a user id, `anonymous` or `system:<label>` as actor (AUD3), sensitive fields are by name only (AUD4), the app cannot update or delete a row (AUD5) |
| LOG | Production log must contain no inline password, email, JWT, or profile value (LOG7, LOG8) |

`INTERNAL_ERROR` anywhere in a response, or any status of 500, is a finding (the error tracker would also get noise).

## You must extend it (the script cannot guess business rules)
For every new operation or feature, add scenarios to `scripts/attack.rb` in the right section, then run again:
1. **Cross-tenant (IDOR).** Two users in two organizations. User B sends the id of user A's record to every query and mutation. The answer must be the same `NOT_FOUND` as for an id that does not exist. Also test ids in nested input and list filters.
2. **Roles.** Each role on each operation. A role that must not do it gets `FORBIDDEN`.
3. **Public operations.** Must be in `Rack::Attack::PUBLIC_OPERATIONS`. Ask: can it be used to guess, enumerate, or spam (same response, same timing for known and unknown input)?
4. **Replay and expiry.** Reused reset or confirmation codes, expired codes, codes after a password change.
5. **Mass assignment.** Extra input fields (`role`, `organizationId`, `id`) must be rejected.
6. **Pagination and lists.** Huge `first`, negative values, deep cursors, N+1 (query count stays flat as data grows).
7. **Webhooks and uploads (when they exist).** Bad signature, replay, oversized or wrong-type files.

## Report
Give the owner a short table: id, severity (Critical, High, Medium, Low), what was sent, what came back, and the fix. Mark what was **not** tested. Never claim "secure"; claim "these attacks failed". Severity guide:
- **Critical/High:** auth bypass, cross-tenant read or write, credentials in logs, no brute-force limit, secrets exposed.
- **Medium:** 500s on bad input, user enumeration, weak validation, missing hardening.
- **Low/Info:** noise, notes, accepted product decisions.

## After fixing
Each finding gets a spec in `spec/` (see `write-tests`) so it cannot return, then run the whole attack again. A fix that only passes the attack script is not done.
