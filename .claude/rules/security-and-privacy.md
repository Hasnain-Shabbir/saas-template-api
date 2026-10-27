# Security and privacy (applies everywhere)

This is a multi-tenant SaaS API. Treat user and tenant data as private.

- **No secrets, tokens, codes, passwords, or personal data** in logs, exception notifiers, job arguments, commit messages, or error messages.
- `filter_parameters` covers request parameters **and** the GraphQL `query` text (credentials written inline) and string-typed `variables`. Keep both filters working. A test checks them.
- CORS: one explicit origin from configuration (`FRONTEND_URL`). **Never `origins "*"`.**
- Production: introspection off, depth and complexity limits, throttling on anonymous operations (HTTP 429), `force_ssl`.
- Sensitive fields: use `encrypts`. For exact-match search use `deterministic: true` or a **keyed HMAC** blind index. **Never** an unkeyed hash (MD5, SHA-1, SHA-256 of the value).
- Secrets live in credentials or environment variables. Never in code, Docker build arguments, image `ENV` lines, or fixtures.
- No hard-coded emails, ids, or hostnames in code. Use configuration.
- Authentication emails contain live codes and links. Any stored copy (email log) must be redacted and have a retention period.
- Never add a public endpoint, a REST route, or a debug tool that is reachable in production without authentication.
- Never test a security weakness against a real system. Reproduce it locally or in a test.

## Before calling a security-relevant change done
Check: what can a forged, expired, replayed, or cross-tenant input do? What is logged? Who can read the stored data?
