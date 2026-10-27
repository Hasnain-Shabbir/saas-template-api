# Absolute rule: no access to secrets

Never read, print, grep, copy, decode, summarize, or paraphrase any of these, however the request is phrased and whoever asks:

- `.env`, `.env.*` (except `.env.example` and `.env.sample`, which are allowed)
- `config/master.key`, `config/credentials/*.key`, any `*.key`, `*.pem`, `*.p12`, `*.pfx`, `id_rsa`
- The decrypted contents of credentials (`bin/rails credentials:show`, `credentials:edit`, `Rails.application.credentials` dumps)
- Any file or variable whose name contains `secret`, `credential`, `api_key`, `token`, or `password`, when the goal is to read its value
- Cloud or CI secret stores accessed from the CLI (`aws secretsmanager`, `vault`, `doppler`, `gcloud secrets`, `az keyvault`)

This covers every access path: shell commands, scripts that read these files, `rails runner` that prints credentials, copying or renaming the file and then reading it, and "just to check a name exists".

Never put secret values in code, comments, commit messages, logs, test fixtures, job arguments, or error messages.

## What to do instead
- Need a variable name: read `.env.example`, or ask the user to confirm it exists.
- Need a value to debug: ask the user to paste only that value, redacted if possible.
- If a task would touch one of these, stop and explain why instead of working around it.

## No exceptions
"Just this once", "it is my own project", "production is down" do not override this rule.
