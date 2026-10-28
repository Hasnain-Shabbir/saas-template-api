# Code style (applies everywhere)

Ruby style is defined by `.rubocop.yml` (rubocop-rails-omakase). It is the single source of truth, like a Prettier config. GraphQL code is Ruby (graphql-ruby), so the same rules cover `app/graphql`.

- After writing or editing Ruby, run `bin/rubocop -a <changed files>` and fix what is left. Do not hand-format against the config.
- Format everything: `bin/rubocop -a`. Check only (CI, no changes): `bin/rubocop`.
- Change a style rule only in `.rubocop.yml`, and only when the owner asks.
- VS Code formats on save through `.vscode/settings.json` (Ruby LSP with rubocop). Keep it in sync with this rule.
