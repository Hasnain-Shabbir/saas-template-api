---
name: graphql-operation
description: Checklist for adding or changing a GraphQL query or mutation (files, naming, login, policy, tenancy, errors, tests). Use when working in app/graphql.
paths:
  - "app/graphql/**"
---

# Add or change a GraphQL operation

Read first: `.claude/rules/graphql-operations.md`, `authorization.md`, `architecture-layers.md`. For type and field design also open `graphql-schema`.

## Ask before writing (no assumptions)
- Which roles may call it? Which may not?
- Is any field sensitive, or hidden for some roles?
- Can it ever reach another organization's data? (It must not.)
- What are the expected failures and their codes?
- Is it public (no login)? Almost never. Say why.

## Steps
1. **Name** it `<Verb><Noun>`. Mutation file: `app/graphql/mutations/<domain>/<snake_name>.rb`, class extends `Mutations::BaseMutation`. Queries go in `Types::QueryType` (or a resolver once large).
2. **Input and payload.** Arguments through one input object when there are several. Payload returns the record plus `errors` for expected failures.
3. **Login.** `BaseMutation#ready?` requires it. Queries call `current_user!` or `current_organization` first. Do not override `ready?` unless the operation is on the short public list (sign up, sign in, password reset, email confirmation).
4. **Authorize** through a policy. Add the method to the policy. Default is deny.
5. **Tenancy.** Start from `current_organization`. Another organization's record is `NOT_FOUND`.
6. **Logic.** One service call (see `architecture-layers.md`). No business logic in the mutation.
7. **Errors.** Expected failures: payload `errors` with a code (`VALIDATION_FAILED`, `CONFLICT`). Access and lookup: top-level `extensions.code`. Never return `exception.message`.
8. **Lists.** Add the list complexity, a maximum size, and no N+1 (dataloader or `includes`).
9. **Register** a new mutation in `types/mutation_type.rb`.
10. **Specs** (see `write-tests`): success, validation failure, unauthenticated, forbidden per role, cross-tenant, and N+1 if it returns a list. Update the policy spec and the permission matrix.

## Done when
- `bundle exec rspec`, `bin/rubocop`, `bin/brakeman -q` all pass (run them, report real output).
- No raw exception text can reach a client, and no secrets or personal data are logged.
- You asked about anything that changes business rules.
