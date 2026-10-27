---
paths:
  - "app/integrations/**"
  - "app/controllers/webhooks*"
---

# Integrations and webhooks

This project has no external integrations yet. These rules apply the day one is added.

- **Every webhook verifies its signature or shared secret, with a constant-time comparison, before anything else.** An endpoint without verification is a bug.
- Store the raw payload first (an inbox table) with a **unique provider event id**, so a replayed event is harmless. Then process it in a job. Answer 2xx quickly.
- One folder per provider under `app/integrations/<provider>/`. Signature validators and payload mappers are small classes of their own.
- Set a timeout on every outbound call. Use an idempotency key for calls that move money or create records.
- Never log full payloads that can hold personal data.
- Money and billing are reconciled by a scheduled job, never assumed correct because a request succeeded.
- No secrets in code. Provider credentials live in Rails credentials.
