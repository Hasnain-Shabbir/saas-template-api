---
paths:
  - "db/**"
  - "app/models/**"
---

# Database and migrations

- **Do not run migrations, rollbacks, or database resets unless the user asks.** Write the migration and say how to run it.
- One change per migration. Reversible. Never edit a migration that has shipped. Add a new one.
- Foreign keys always have an explicit `ON DELETE` and an index. Unique indexes express business rules. Composite indexes match the filter and sort order of the screen that uses them.
- Safe patterns on tables that already have data:
  - add indexes with `algorithm: :concurrently` (and `disable_ddl_transaction!`)
  - add foreign keys and `CHECK` constraints `NOT VALID`, then validate in a separate step
  - add a `NOT NULL` column in steps (nullable, backfill in batches, then constrain)
  - backfill data in a job or a separate migration, never inside a schema migration
- Types: money as integer cents plus a currency column (never `float`), `citext` for emails, timestamps with time zone.
- Every tenant table has `organization_id NOT NULL`. A child of a tenant table carries it too, and the foreign key is **composite** so a cross-tenant link is impossible.
- Search over text uses a generated column and a trigram index, not `ILIKE '%x%'` on an unindexed column.

