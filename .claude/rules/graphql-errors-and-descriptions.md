---
paths:
  - "app/graphql/**"
  - "app/lib/**"
---

# GraphQL errors and descriptions

Builds on `graphql-operations.md` and `errors-and-logging.md`. Those two define the error kinds and the "never return `exception.message`" rule. This file keeps every operation consistent.

## Errors: one place, one shape
- All error codes and client messages live in **one central module**. No inline message strings and no inline code strings in mutations, resolvers, or services.
- A new error is added to the central module first, then used. A typo in a code must fail loudly (a constant that does not exist), not return a wrong string.
- Raise or return errors only through the project's single error helper. Never raise a bare `GraphQL::ExecutionError` with a custom string.
- Every error has the same shape: `message` plus a stable `code` (`extensions.code` for top-level errors, `code` in `errors { message path code }` for errors as data).
- Messages are safe for end users, short, and in plain English. No class names, SQL, paths, or record ids.
- Unknown errors become one generic internal error code. Details go to the log and the error tracker, never to the client.
- No I18n or locale files. Messages are constants in the central module.

## Success responses
- Every mutation payload follows the same shape. A new payload shape needs approval.
- Success messages (for example "logged out") also come from the central module, not inline strings.

## Descriptions
- Every type, field, argument, and mutation has a `description`: one short sentence in plain English.
- Mutation descriptions start with a verb and name any side effect (for example "Ends the current session. Its token stops working immediately.").
- A description never contains secrets, internal hostnames, or anything that should not be public.
- One schema spec fails if any type, field, or argument has no description. A new operation without a description is incomplete.
