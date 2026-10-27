---
name: db-migration-review
description: Review-only check of a Rails migration or schema change for locks, constraints, indexes, reversibility, and data safety. Use when a file in db/migrate is created or changed.
paths:
  - "db/migrate/**"
disallowed-tools: Edit Write
---

# Review a migration (report only, never edit)

Read `.claude/rules/database-and-migrations.md` first. Report findings with file and line, a severity, and a suggested fix. Do not change files. Do not run the migration.

## Checklist
**Safety on tables that already have data**
- [ ] One change per migration. Has a working `down` (or `change` that reverses).
- [ ] Index added with `algorithm: :concurrently` and `disable_ddl_transaction!`.
- [ ] Foreign key or `CHECK` added `NOT VALID`, validated in a separate step.
- [ ] `NOT NULL` added in steps: nullable column, batched backfill, then the constraint.
- [ ] No data backfill or app-model call inside the schema migration (models change, migrations must not).
- [ ] Drop or rename of a column or table: needs expand and contract across deploys. Flag it and ask.

**Integrity**
- [ ] Every foreign key has an explicit `ON DELETE` and an index.
- [ ] Business rules are unique indexes or `CHECK`s, not only validations.
- [ ] Status and role columns are strings with a `CHECK`.
- [ ] Tenant tables have `organization_id NOT NULL`; children use a composite foreign key.

**Types**
- [ ] Money: integer cents plus currency. Never float.
- [ ] Emails: `citext`. Times: with time zone.
- [ ] No `ILIKE '%x%'` search without a trigram index.

**Hygiene**
- [ ] `strong_migrations` is not installed unless added later. Apply its rules by hand and say so.
- [ ] Not editing a migration that already shipped.

## Output
```
[HIGH] db/migrate/2026..._x.rb:12  add_index without concurrently on accounts
  Why: locks writes on a large table.
  Fix: algorithm: :concurrently plus disable_ddl_transaction!.
```
End with: what you verified by reading, and what you did not (you did not run it).
