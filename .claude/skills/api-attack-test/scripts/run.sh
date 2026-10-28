#!/usr/bin/env bash
# Runs the attack suite against two LOCAL servers (test mode and production mode), then cleans up.
# Usage: .claude/skills/api-attack-test/scripts/run.sh [output_dir]   (default output_dir: tmp/attack-test)
# Touches the TEST database only. Never reads secrets: the production-mode key is random and thrown away.
set -u
cd "$(git rev-parse --show-toplevel)"
OUT="${1:-tmp/attack-test}"; mkdir -p "$OUT"
HERE=".claude/skills/api-attack-test/scripts"

DB=$(RAILS_ENV=test bin/rails runner 'print ActiveRecord::Base.connection.current_database' 2>/dev/null | tail -1)
case "$DB" in *_test) ;; *) echo "Refusing to run: database '$DB' is not a test database"; exit 1;; esac

truncate_db() { RAILS_ENV=test bin/rails runner 'ActiveRecord::Base.connection.execute("TRUNCATE users CASCADE")' >/dev/null 2>&1; }
cleanup() { [ -f "$OUT/t.pid" ] && kill "$(cat "$OUT/t.pid")" 2>/dev/null; [ -f "$OUT/p.pid" ] && kill "$(cat "$OUT/p.pid")" 2>/dev/null; sleep 1; truncate_db; }
trap cleanup EXIT

PUBLIC_OPS=$(RAILS_ENV=test bin/rails runner 'print Rack::Attack::PUBLIC_OPERATIONS.join(",")' 2>/dev/null | tail -1)
truncate_db

RAILS_ENV=test bin/rails server -p 4001 -b 127.0.0.1 -P "$OUT/t.pid" > "$OUT/server_test.log" 2>&1 &
SECRET_KEY_BASE=$(openssl rand -hex 64) RAILS_ENV=production APP_HOST=127.0.0.1 FRONTEND_URL=http://localhost:3000 MAILER_FROM=no-reply@example.test \
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
sleep 1
{
  echo "LOG1 inline password in log:  $(grep -c "PW-$MARK" "$OUT/server_prod.log")  (want 0)"
  echo "LOG2 inline email in log:     $(grep -c "$MARK@example" "$OUT/server_prod.log")  (want 0)"
  echo "LOG3 JWT in log:              $( [ -n "$TOKEN" ] && grep -c "${TOKEN:0:40}" "$OUT/server_prod.log" || echo 0)  (want 0)"
  echo "LOG4 'Bearer ' in log:        $(grep -c 'Bearer ' "$OUT/server_prod.log")  (want 0)"
  echo "LOG5 stack traces for 500s:   $(grep -c 'Puma caught this error' "$OUT/server_test.log")  (want 0)"
} | tee "$OUT/log_check.txt"

echo; for f in test prod; do tail -1 "$OUT/$f.out"; done
echo; echo "Problems (anything not PASS/INFO):"; grep -hE '^\[(FAIL|CRITICAL|WEAK|CHECK)\]' "$OUT/test.out" "$OUT/prod.out" | cut -c1-260
echo; echo "Full output: $OUT/test.out, $OUT/prod.out, $OUT/log_check.txt"
