---
paths:
  - "app/**"
  - "config/**"
---

# Errors and logging

- Errors carry a stable `code`. The message is safe for end users. Internal detail goes to the log and the error tracker only.
- Never send `exception.message`, a SQL fragment, a class name, or a path to a client.
- Do not swallow errors: no bare `rescue`, no `rescue => e` that returns `e.message`. Rescue the specific error you can handle.
- Log at `info` in production, with the request id. No payload dumps, no parameters with personal data.
- No debug output (`p`, `puts`, `pp`, `binding.irb`, `byebug`) in committed code.
- An exception notifier must not receive GraphQL variables or credentials. Scrub first.
- A failed background job is visible (retry, then dead set or error report), never silently dropped.
