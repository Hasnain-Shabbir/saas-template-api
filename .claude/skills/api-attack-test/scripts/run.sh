#!/usr/bin/env bash
# Runs the attack suite against two LOCAL servers (test mode and production mode), then cleans up.
# Usage: .claude/skills/api-attack-test/scripts/run.sh [output_dir]   (default output_dir: tmp/attack-test)
# Both servers get ALLOW_PUBLIC_SIGN_UP=true (the template default is off): the script uses signUp to make its users.
# Touches the TEST database only. Never reads secrets: the production-mode key is random and thrown away.
set -u
cd "$(git rev-parse --show-toplevel)"
OUT="${1:-tmp/attack-test}"; mkdir -p "$OUT"
HERE=".claude/skills/api-attack-test/scripts"

DB=$(RAILS_ENV=test bin/rails runner 'print ActiveRecord::Base.connection.current_database' 2>/dev/null | tail -1)
case "$DB" in *_test) ;; *) echo "Refusing to run: database '$DB' is not a test database"; exit 1;; esac

# The audit, read audit and email log tables have no foreign key to users, so `users CASCADE` alone leaves their rows behind (and specs that expect an empty table then fail).
truncate_db() { RAILS_ENV=test bin/rails runner 'ActiveRecord::Base.connection.execute("TRUNCATE users, audit_versions, read_audits, email_logs CASCADE")' >/dev/null 2>&1; }
cleanup() { [ -f "$OUT/t.pid" ] && kill "$(cat "$OUT/t.pid")" 2>/dev/null; [ -f "$OUT/p.pid" ] && kill "$(cat "$OUT/p.pid")" 2>/dev/null; sleep 1; truncate_db; }
trap cleanup EXIT

PUBLIC_OPS=$(RAILS_ENV=test bin/rails runner 'print Rack::Attack::PUBLIC_OPERATIONS.join(",")' 2>/dev/null | tail -1)
truncate_db

ALLOW_PUBLIC_SIGN_UP=true RAILS_ENV=test bin/rails server -p 4001 -b 127.0.0.1 -P "$OUT/t.pid" > "$OUT/server_test.log" 2>&1 &
ALLOW_PUBLIC_SIGN_UP=true SECRET_KEY_BASE=$(openssl rand -hex 64) RAILS_ENV=production \
  ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$(openssl rand -hex 32) ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$(openssl rand -hex 32) ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$(openssl rand -hex 32) APP_HOST=127.0.0.1 FRONTEND_URL=http://localhost:3000 MAILER_FROM=no-reply@example.test \
  DATABASE_URL="postgresql://$(whoami)@localhost/$DB" bin/rails server -p 4002 -b 127.0.0.1 -P "$OUT/p.pid" > "$OUT/server_prod.log" 2>&1 &
for i in $(seq 1 30); do
  curl -s -o /dev/null -m1 localhost:4001/up && curl -s -o /dev/null -m1 -H 'Host: 127.0.0.1' localhost:4002/up && break; sleep 1
done

bundle exec ruby "$HERE/attack.rb" http://127.0.0.1:4001 test "$OUT/test.json" "$PUBLIC_OPS" > "$OUT/test.out" 2>&1
bundle exec ruby "$HERE/attack.rb" http://127.0.0.1:4002 prod "$OUT/prod.json" "$PUBLIC_OPS" > "$OUT/prod.out" 2>&1

# Log leak check: credentials written inline and a live token must not appear in the log.
MARK="leak$(openssl rand -hex 4)"
curl -s -o /dev/null -XPOST localhost:4002/graphql -H 'content-type: application/json' -H 'X-Forwarded-For: 10.250.1.1' \
  -d "{\"query\":\"mutation{signUp(input:{email:\\\"$MARK@example.test\\\",password:\\\"PW-$MARK-long-enough\\\"}){token}}\"}"
TOKEN=$(curl -s -XPOST localhost:4002/graphql -H 'content-type: application/json' -H 'X-Forwarded-For: 10.250.1.2' \
  -d "{\"query\":\"mutation{login(input:{email:\\\"$MARK@example.test\\\",password:\\\"PW-$MARK-long-enough\\\"}){token}}\"}" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
curl -s -o /dev/null -XPOST localhost:4002/graphql -H 'content-type: application/json' -H "Authorization: Bearer $TOKEN" -d '{"query":"{me{id}}"}'
curl -s -o /dev/null -XPOST localhost:4002/graphql -H 'content-type: application/json' -H 'X-Forwarded-For: 10.250.1.3' \
  -d "{\"query\":\"mutation(\$i: ResetPasswordInput!){resetPassword(input:\$i){success}}\",\"variables\":{\"i\":{\"email\":\"x@example.test\",\"code\":\"CODE-$MARK\",\"password\":\"PW-$MARK-other\"}}}"
curl -s -o /dev/null -XPOST localhost:4002/graphql -H 'content-type: application/json' -H "Authorization: Bearer $TOKEN" \
  -d "{\"query\":\"mutation(\$i: UpdateProfileInput!){updateProfile(input:\$i){errors{code}}}\",\"variables\":{\"i\":{\"firstName\":\"FN-$MARK\",\"lastName\":\"LN-$MARK\",\"dateOfBirth\":\"1971-03-09\",\"phone\":\"+14155550199\"}}}"
curl -s -o /dev/null -XPOST localhost:4002/graphql -H 'content-type: application/json' -H "Authorization: Bearer $TOKEN" \
  -d "{\"query\":\"mutation{updateProfile(input:{firstName:\\\"FNI-$MARK\\\",lastName:\\\"LNI-$MARK\\\",dateOfBirth:\\\"1971-03-09\\\",phone:\\\"+14155550199\\\"}){errors{code}}}\"}"
sleep 1
{
  echo "LOG1 inline password in log:  $(grep -c "PW-$MARK" "$OUT/server_prod.log")  (want 0)"
  echo "LOG2 inline email in log:     $(grep -c "$MARK@example" "$OUT/server_prod.log")  (want 0)"
  echo "LOG3 JWT in log:              $( [ -n "$TOKEN" ] && grep -c "${TOKEN:0:40}" "$OUT/server_prod.log" || echo 0)  (want 0)"
  echo "LOG4 'Bearer ' in log:        $(grep -c 'Bearer ' "$OUT/server_prod.log")  (want 0)"
  echo "LOG6 one-time code variable:  $(grep -c "CODE-$MARK" "$OUT/server_prod.log")  (want 0)"
  echo "LOG7 profile names in log:    $(grep -c "FN-$MARK\|LN-$MARK\|FNI-$MARK\|LNI-$MARK" "$OUT/server_prod.log")  (want 0)"
  echo "LOG8 phone or birth date:     $(grep -c '+14155550199\|1971-03-09' "$OUT/server_prod.log")  (want 0)"
  echo "LOG5 stack traces for 500s:   $(grep -c 'Puma caught this error' "$OUT/server_test.log")  (want 0)"
} | tee "$OUT/log_check.txt"

echo; for f in test prod; do tail -1 "$OUT/$f.out"; done
echo; echo "Problems (anything not PASS/INFO):"; grep -hE '^\[(FAIL|CRITICAL|HIGH|MEDIUM|LOW|WEAK|CHECK)\]' "$OUT/test.out" "$OUT/prod.out" | cut -c1-260
echo; echo "Full output: $OUT/test.out, $OUT/prod.out, $OUT/log_check.txt"
