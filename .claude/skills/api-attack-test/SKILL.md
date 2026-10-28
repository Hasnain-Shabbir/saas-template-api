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
| LOG | Production log must contain no inline password, email, or JWT |

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
