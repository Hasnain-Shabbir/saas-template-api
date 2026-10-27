---
paths:
  - "spec/**"
---

# Testing (RSpec)

This project uses RSpec with FactoryBot (no fixtures).

- `spec/` mirrors `app/`. Test through the layer's public face: GraphQL request tests for operations, unit specs for services, policy tests, model tests for constraints.
- Every operation has: a success case, a validation failure, an unauthenticated case, a forbidden case, and a **cross-tenant** case.
- Security paths have **negative tests**: forged or garbage token, expired token, token after logout, replayed or expired code, enumeration (same response for known and unknown email).
- Keep the **coverage tests** (operations versus permission tests, list fields versus complexity multiplier). Add to them, never loosen them.
- Factories: build the smallest valid record. Add traits for roles instead of editing the base factory.
- No real network and no sleeping. Use `travel` for time.
- Rate-limit tests swap in a memory store and restore the null store afterwards.
- Run the whole suite, `bin/rubocop`, and `bin/brakeman -q` before saying a change is done. Report failures with their output. Never claim green without running.

## Commands
```
bundle exec rspec
bundle exec rspec spec/graphql/auth_spec.rb
bin/rubocop
bin/brakeman -q
```
