---
name: write-tests
description: RSpec conventions and the required cases for GraphQL operations, services, policies, and security paths. Use when creating or editing files in spec/.
paths:
  - "spec/**"
---

# Writing tests (RSpec)

Read `.claude/rules/testing.md`. Write specs for the step being built, no more.

## Where
`spec/` mirrors `app/`: `spec/graphql/` (operations), `spec/policies/`, `spec/models/`, `spec/services/`, `spec/jobs/`, `spec/requests/` (middleware, rate limiting, webhooks), `spec/factories/`.

## Helpers
No shared helpers exist yet. When the first request spec needs them, add them under `spec/support/` (for example `graphql_context(user)` and `auth_headers(user)`) and list them here.

## Cases every operation needs
1. Success.
2. Validation failure (error `code` and `path`).
3. Unauthenticated.
4. Forbidden, for each role that must not do it.
5. Cross-tenant (another organization's record is `NOT_FOUND`).
6. List operations: no N+1 and the complexity multiplier.

## Security paths need negative tests
Garbage, expired, and post-logout tokens. Wrong password. Unknown email returns the same response as a known one. Reused or expired reset token.

## Rules
- Keep the coverage specs (operations versus permission specs, list fields versus complexity). Never loosen them.
- No real network, no `sleep`. Use `travel_to` for time.
- Rate-limit specs use a memory store and restore the original store in an `after` hook.
- Assert behavior and error codes, not private methods.
- FactoryBot: the smallest valid record, traits for roles. Prefer `build` over `create` when the database is not needed.
- Jobs and mailers: assert enqueueing with the Active Job test helpers. Do not run Sidekiq in specs.

## Run and report
```
bundle exec rspec
bundle exec rspec spec/graphql/auth_spec.rb
bin/rubocop
bin/brakeman -q
```
Report real output. Never claim green without running.
