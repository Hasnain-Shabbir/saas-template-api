---
name: security-review-backend
description: Review-only security check of authentication, authorization, tenancy, logging, CORS, and production settings. Use when changing auth, policies, GraphQL access, or config.
paths:
  - "app/graphql/**"
  - "app/controllers/graphql_controller.rb"
  - "app/policies/**"
  - "app/models/user.rb"
  - "config/initializers/**"
disallowed-tools: Edit Write
---

# Backend security review (report only, never edit)

Read `.claude/rules/security-and-privacy.md` and `authentication-and-sessions.md` first. Also open `brakeman` for scanner output. Report findings with file and line and a severity. Do not change files. **Never test a weakness against a real system. Reproduce it in a spec or reason from the code.**

## Checklist
**Authentication and sessions**
- [ ] No `JWT.decode` with verification off anywhere (search the whole app).
- [ ] Tokens revocable. Logout, password change, and reset revoke them.
- [ ] Sign in, reset, and lockout give one message for unknown email, wrong password, and locked account.
- [ ] Reset and confirmation tokens single use and short lived. Passwords never logged.

**Authorization and tenancy**
- [ ] Every operation calls a policy. Default deny holds (`ApplicationPolicy`).
- [ ] Every query starts from `current_organization`. No global `find`.
- [ ] Cross-tenant ids return `NOT_FOUND`.
- [ ] Field-level hiding exists where a role must not see a field.

**Data and logs**
- [ ] `filter_parameters` covers the GraphQL `query` text and string `variables`.
- [ ] No secrets, codes, or personal data in job arguments, logs, exception notifiers, or error messages.
- [ ] Sensitive fields: `encrypts`, with keyed or deterministic search, never an unkeyed hash.
- [ ] Authentication emails: stored copies are redacted and have a retention period.

**Configuration**
- [ ] CORS has one explicit origin, never `*`.
- [ ] Production: introspection off, depth and complexity limits, throttling on anonymous operations, `force_ssl`.
- [ ] The Sidekiq web UI is behind authentication, or not mounted.
- [ ] No secrets in code, Docker build args, image `ENV`, or factories. No hard-coded emails or ids.
- [ ] No unauthenticated endpoint or dev tool reachable in production.

**Evidence**
- Run `bin/brakeman -q` and summarize. Run `bundle exec bundle-audit check` if it is available.
- Negative specs exist for: garbage, expired, and post-logout tokens; wrong password; unknown email; reused reset token; cross-tenant access.

## Output
List findings by severity (Critical, High, Medium, Low) as `[SEV] path:line  what / why / suggested fix`. Then state clearly what was **verified by reading**, what was **run**, and what was **not checked**.
