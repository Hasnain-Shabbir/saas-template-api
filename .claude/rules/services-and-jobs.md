---
paths:
  - "app/services/**"
  - "app/jobs/**"
  - "app/mailers/**"
---

# Services, jobs, and mailers

## Services
- One class is one use case (`Accounts::Create`). One public method, `call`. It returns a `Result`: success with a value, or failure with a stable `code` and safe `message`.
- A query object (`Domain::SearchQuery`) is the one exception to the `Result` rule: it only builds a filtered, ordered relation and returns it. It has no rules, no transaction, no side effects. A use case calls it.
- Rescue only errors you can handle. **Never** `rescue StandardError` and return `e.message`. Unknown errors propagate to the error tracker.
- A service owns the transaction. Side effects that can fail later (email, provider calls) go to a job **after** the commit.

## Jobs (Active Job on Sidekiq)
- Arguments are ids only. No secrets, tokens, passwords, or personal data in arguments.
- Jobs are idempotent: running one twice must be safe.
- Declare `retry_on` and `discard_on` explicitly. A job whose record was deleted is discarded, not retried forever.
- Name the queue. Keep jobs thin: load by id, call a service.
- `config.active_job.log_arguments = false` stays on (job arguments are not logged).

## Mailers
- Send with `deliver_later`. Mail must not contain sensitive data. Email is not a secure channel.
- Authentication emails carry codes and links. Treat their stored copies as secrets (see `security-and-privacy.md`).

