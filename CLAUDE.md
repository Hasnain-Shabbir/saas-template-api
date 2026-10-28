# SaaS Template API

A multi-tenant GraphQL API template. Rails 8.1 (API only), Ruby 3.4.2, PostgreSQL. Planned stack: Devise with devise-jwt (auth), graphql-ruby, Sidekiq (jobs and mailers), RSpec with FactoryBot. Gems are added one step at a time, only when needed.

Detailed project rules live in `.claude/rules/*.md` and load automatically. Rules with a `paths:` header load only when matching files are in play. Read the rule for the area you are about to change.

Rules that name a tool not installed yet (Pundit, rack-attack, the allowlist for JWT revocation) describe the target. Ask before choosing a different tool.

## Skills (`.claude/skills/`)
Loaded on demand. Only each skill's short description is always in context, and the body loads when it is used.
- Vendored third party (sources, commits, and patches in `.claude/skills-sources.json`): `graphql-schema`, `postgresql-table-design`, `ruby`, `brakeman`.
- Our own: `graphql-operation`, `write-tests`, `api-attack-test` (run before a push), `db-migration-review` (review only), `security-review-backend` (review only).
- **Project rules in `.claude/rules/` override vendored skills** when they differ. Known case: the `ruby` skill prefers `fail` over `raise`. This project uses `raise`.

## Commands
```
bin/rails server         # dev server
bundle exec rspec        # whole suite
bin/rubocop              # style check
bin/rubocop -a           # format all Ruby (auto-fix)
bin/brakeman -q          # security scan
```

## Most important rules (details in `.claude/rules/`)
- Claude does the setup step by step and explains each step. No extra changes. No migrations unless asked.
- Never read secrets or `.env` files. Never put secrets or personal data in logs.
- Default deny: login required, policies for every operation, tenancy through the current tenant.
- Never return `exception.message` to a client. Never decode a JWT without verification.
- Commit only when asked, stage by path, `type: message`, no `Co-Authored-By`.
