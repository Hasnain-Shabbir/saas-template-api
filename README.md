# SaaS Template API

A GraphQL API template. Rails 8.1 (API only), Ruby 3.4.2, PostgreSQL, Devise + JWT, Pundit, graphql-ruby, Sidekiq.

## What you need installed
- Ruby 3.4.2 (see `.ruby-version`)
- PostgreSQL
- Redis (Sidekiq stores its jobs there)
- Mailpit (catches development emails, free and open source)

On macOS:
```
brew install redis mailpit
brew services start redis      # or run: redis-server
```

## First setup
```
bundle install
bin/rails db:create db:migrate
cp .env.example .env           # then edit the values. Never commit .env
```

## Configuration
Settings come from environment variables. Never put secrets in code or commit them.
`.env.example` documents the variables for background jobs and mail:

| Variable | Used for | Default (development) |
|---|---|---|
| `REDIS_URL` | Sidekiq's Redis | local Redis (`redis://localhost:6379/0`) |
| `SIDEKIQ_CONCURRENCY` | Sidekiq threads per process | 5 |
| `SMTP_HOST`, `SMTP_PORT` | Where development mail is sent (Mailpit) | `localhost`, `1025` |

Other variables the app reads: `APP_HOST` (required in production), `FRONTEND_URL`, `MAILER_FROM`,
`SUPER_ADMIN_EMAIL` and `SUPER_ADMIN_PASSWORD` (used by `bin/rails db:seed` to create the first super admin).

## Running the app in development
Start each in its own terminal:
```
redis-server                   # skip if started with brew services
mailpit                        # SMTP on 1025, inbox at http://localhost:8025
bin/rails server               # the API
bundle exec sidekiq            # the worker that runs background jobs and sends mail
```
Restart Sidekiq after you change code in a job or any config. It loads them once at start.

## Background jobs and email
- Jobs run through Active Job on **Sidekiq**. Queues are in `config/sidekiq.yml` (`mailers`, `default`).
  A failed job is retried up to 5 times, then goes to the dead set.
- In the test environment jobs use the `:test` adapter, so tests need no Redis.
- Job arguments are ids only, and `log_arguments` is off, so no secrets or personal data reach the logs.
- The Sidekiq web UI is **not** mounted. If it is ever added, it must require authentication.
- Development email is sent to Mailpit. Open http://localhost:8025 to read it (for example the password reset code).
  Mailpit keeps mail in memory only, so it is gone when you stop it.

### How to tell that jobs work
1. Request an action that sends mail (for example a password reset).
2. The server log shows `Enqueued ... to Sidekiq(mailers)`.
3. The Sidekiq terminal shows `start`, then `done`.
4. The mail appears in Mailpit.

If Sidekiq says `done` but there is no mail, the problem is delivery (is Mailpit running?), not Sidekiq.

### Debug commands
```
redis-cli ping                 # PONG means Redis is up
redis-cli llen queue:mailers   # jobs waiting in the mailers queue
redis-cli zcard retry          # jobs that failed and wait for a retry
redis-cli zcard dead           # jobs that gave up
bin/rails runner 'puts Sidekiq::Stats.new.then { |s| [s.processed, s.failed, s.enqueued, s.retry_size, s.dead_size].inspect }'
```

## Checks
```
bundle exec rspec              # whole test suite
bin/rubocop                    # style check (bin/rubocop -a fixes it)
bin/brakeman -q                # security scan
```
