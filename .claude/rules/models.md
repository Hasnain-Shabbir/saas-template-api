---
paths:
  - "app/models/**"
---

# Models

- A validation is not a constraint. Every rule that matters also exists in the database: `NOT NULL`, `UNIQUE`, `CHECK`, foreign key. Add the constraint in the same change as the validation.
- Enums are **strings with a `CHECK` constraint** (`enum :role, { admin: "admin", ... }, validate: true` plus a database `CHECK`). Never integers: they cannot be reordered or reused safely.
- Use a timestamp, not a boolean, for state that has a time (`archived_at`, `locked_at`).
- Normalize input in the model (`normalizes :email`).
- Callbacks only shape data of the same record. No external calls, no email, no business decisions. A job may be enqueued only from `after_commit`, and it loads by id.
- Concerns are small, named for a behavior, one level deep. A model over about 200 lines is a signal to extract a service or a query object.
- Associations declare `dependent:` on purpose (`restrict_with_exception` is the default choice for tenant data).
- Sensitive personal fields are candidates for `encrypts`. Exact-match search uses `deterministic: true` or a keyed HMAC index. Never an unkeyed hash.

