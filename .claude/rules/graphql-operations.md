---
paths:
  - "app/graphql/**"
---

# GraphQL operations

- Mutations extend `Mutations::BaseMutation` (Relay classic: input object plus `clientMutationId`). Name every operation `<Verb><Noun>`. Never rename one without checking every client that uses it by name.
- **Default deny.** `BaseMutation#ready?` requires login. Only `login`, `requestPasswordReset`, and `resetPassword` override it, and the list of public operations stays this short. Queries call `current_user!` or `current_organization` first.
- Every operation authorizes through a Pundit policy (`authorize!(record, :query?)`). A new operation without a permission test is incomplete.
- **Errors, two kinds, both kept:**
  - Expected failures are data: `errors { message path code }` with codes `VALIDATION_FAILED`, `CONFLICT`, `INVALID_CREDENTIALS`.
  - Access and lookup problems are top-level errors with `extensions.code`: `UNAUTHENTICATED`, `FORBIDDEN`, `NOT_FOUND`.
  - **Never return `exception.message` to the client.** Unknown errors become a generic message and go to logs and the error tracker.
- Tenancy: a record from another organization returns the same `NOT_FOUND` as a missing one.
- N+1: use the dataloader (or `includes` in a query object). The N+1 test must keep passing.
- Limits live in `saas_template_api_schema.rb`: `max_depth`, `max_complexity`, `max_query_string_tokens`, introspection off in production. Do not raise a limit to make one query pass without asking.
- Every list field of objects carries `complexity: Types::BaseField::LIST_COMPLEXITY`. A test fails if one does not.
- Field-level hiding (for example an email hidden from some roles) lives in the type and has a test.

