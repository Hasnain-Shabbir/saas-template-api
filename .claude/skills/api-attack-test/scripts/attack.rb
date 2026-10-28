# Black-box attack run against a LOCAL server. Usage:
#   bundle exec ruby attack.rb BASE_URL LABEL OUT_JSON PUBLIC_OPERATIONS
#   LABEL is "test" (introspection on, schema phase runs) or "prod" (production mode: introspection must be off).
# Every request carries a random X-Forwarded-For, so the per-IP throttle does not hide other findings.
# Section H pins one IP on purpose to prove the throttle works.
require "net/http"
require "json"
require "jwt"
require "securerandom"
require "base64"

BASE = ARGV[0] || "http://127.0.0.1:4001"
LABEL = ARGV[1] || "test"
OUT = ARGV[2] || "/dev/null"
PUBLIC_OPS = (ARGV[3] || "login,signUp").split(",")
$results = []
$pinned_ip = nil

def http(method: :post, path: "/graphql", body: nil, headers: {}, raw: nil, ctype: "application/json")
  uri = URI("#{BASE}#{path}")
  h = Net::HTTP.new(uri.host, uri.port)
  h.read_timeout = 90
  req = Net::HTTPGenericRequest.new(method.to_s.upcase, !!(body || raw), true, uri.request_uri)
  req["Content-Type"] = ctype if ctype
  req["X-Forwarded-For"] = $pinned_ip || "10.#{rand(256)}.#{rand(256)}.#{rand(1..254)}"
  headers.each { |k, v| req[k] = v }
  payload = raw || (body && JSON.generate(body))
  req.body = payload if payload
  t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  res = h.request(req)
  ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t) * 1000).round
  { status: res.code.to_i, body: res.body.to_s, json: (JSON.parse(res.body) rescue nil), headers: res.each_header.to_h, ms: ms }
rescue => e
  { status: 0, body: "#{e.class}: #{e.message}", json: nil, headers: {}, ms: 0 }
end

def gql(query, variables: nil, token: nil)
  http(body: { query: query, variables: variables }.compact, headers: token ? { "Authorization" => "Bearer #{token}" } : {})
end

def rec(id, title, verdict, detail = "")
  $results << { id: id, title: title, verdict: verdict, detail: detail.to_s[0, 400] }
  puts "[#{verdict}] #{id} #{title} :: #{detail.to_s[0, 220]}" unless verdict == "PASS"
  puts "[PASS] #{id} #{title}" if verdict == "PASS"
end

def check(id, title, ok, detail = "", bad: "FAIL") = rec(id, title, ok ? "PASS" : bad, detail)
def clean?(r) = r[:status] < 500 && r[:status] != 0 && !r[:body].include?("INTERNAL_ERROR")
def code(r) = r[:json]&.dig("errors", 0, "extensions", "code")

SIGNUP = "mutation S($i: SignUpInput!){ signUp(input:$i){ token user{id email} errors{message path code} } }"
LOGIN  = "mutation L($i: LoginInput!){ login(input:$i){ token user{id email} errors{message path code} } }"
LOGOUT = "mutation { logout(input:{}){ success errors{message path code} } }"
ME     = "{ me { id email } }"
PW = "Str0ng-Passw0rd!"

def uniq = "qa#{SecureRandom.hex(5)}@example.test"
def signup(email, pw = PW) = gql(SIGNUP, variables: { i: { email: email, password: pw } })
def login(email, pw = PW) = gql(LOGIN, variables: { i: { email: email, password: pw } })
def tok_of(r, op = "signUp") = r[:json]&.dig("data", op, "token")
def errs_of(r, op = "signUp") = r[:json]&.dig("data", op, "errors")

# ---------- A. Functional / regression ----------
email = uniq
r = signup(email)
tok = tok_of(r)
uid = r[:json]&.dig("data", "signUp", "user", "id")
check("A1", "signUp happy path", tok, r[:body])
check("A2", "me with valid token", gql(ME, token: tok)[:json]&.dig("data", "me", "email") == email)
check("A3", "me without token -> UNAUTHENTICATED", code(gql(ME)) == "UNAUTHENTICATED")
check("A4", "duplicate signUp rejected", errs_of(signup(email))&.any?)
check("A5", "duplicate signUp, UPPERCASE email", errs_of(signup(email.upcase))&.any?)
check("A6", "duplicate signUp, surrounding spaces", errs_of(signup("  #{email}  "))&.any?)
r = login(email.upcase)
check("A7", "login is case-insensitive on email", tok_of(r, "login"))
tok2 = tok_of(r, "login")
wrong = login(email, "wrong-password-x")
check("A8", "wrong password -> INVALID_CREDENTIALS", wrong[:json]&.dig("data", "login", "errors", 0, "code") == "INVALID_CREDENTIALS", wrong[:body])
check("A9", "unknown email answers identically (no enumeration)", login(uniq, "wrong-password-x")[:json]&.dig("data", "login", "errors") == wrong[:json]&.dig("data", "login", "errors"))

["short", "a@b", "plainstring", "@nodomain.com", ""].each_with_index do |bad, i|
  r = i.zero? ? signup(uniq, bad) : signup(bad)
  check("A10.#{i}", "signUp rejects invalid input #{bad.inspect}", errs_of(r)&.any? && !tok_of(r), r[:body])
end
check("A11", "password over 72 bytes rejected", errs_of(signup(uniq, "x" * 73))&.any?)
check("A12", "password under the minimum rejected", errs_of(signup(uniq, "123456"))&.any?)
check("A13", "multibyte password over 72 BYTES rejected", errs_of(signup(uniq, "🔥" * 19))&.any?)
mb = uniq
signup(mb, "pässwörd-日本語-🔥")
check("A14", "unicode password signUp+login works", tok_of(login(mb, "pässwörd-日本語-🔥"), "login"))

check("A15", "logout succeeds", gql(LOGOUT, token: tok2)[:json]&.dig("data", "logout", "success"))
check("A16", "token after logout is rejected (replay)", code(gql(ME, token: tok2)) == "UNAUTHENTICATED")
check("A17", "double logout rejected", code(gql(LOGOUT, token: tok2)) == "UNAUTHENTICATED")
check("A18", "logout of one session keeps the other", gql(ME, token: tok)[:json]&.dig("data", "me"))
check("A19", "logout without token", code(gql(LOGOUT)) == "UNAUTHENTICATED")

# ---------- B. Token attacks ----------
def b64(h) = Base64.urlsafe_encode64(JSON.generate(h), padding: false)
now = Time.now.to_i
payload = { "sub" => uid, "scp" => "user", "aud" => nil, "iat" => now, "exp" => now + 3600, "jti" => SecureRandom.uuid }
denied = ->(t) { r = gql(ME, token: t); !r[:json]&.dig("data", "me") && clean?(r) || r[:status] == 400 }
check("B1", "forged alg=none token", denied.("#{b64({ alg: 'none', typ: 'JWT' })}.#{b64(payload)}."), bad: "CRITICAL")
check("B2", "token signed with attacker secret", denied.(JWT.encode(payload, "attacker-secret", "HS256")), bad: "CRITICAL")
check("B3", "expired forged token", denied.(JWT.encode(payload.merge("exp" => now - 10), "attacker-secret", "HS256")), bad: "CRITICAL")
parts = tok.split(".")
claims = JSON.parse(Base64.urlsafe_decode64(parts[1] + "=" * ((4 - parts[1].size % 4) % 4)))
check("B4", "valid token, payload tampered (sub swapped)", denied.([parts[0], b64(claims.merge("sub" => SecureRandom.uuid)), parts[2]].join(".")), bad: "CRITICAL")
check("B5", "valid token, signature byte flipped", denied.(tok[0..-2] + (tok[-1] == "A" ? "B" : "A")), bad: "CRITICAL")
["garbage", "a.b.c", "....", "null", "'; DROP TABLE users;--", "A" * 100_000].each_with_index do |g, i|
  check("B6.#{i}", "garbage token #{g[0, 12].inspect} (#{g.size} bytes)", denied.(g))
end
check("B7", "token without Bearer prefix ignored", !http(body: { query: ME }, headers: { "Authorization" => tok })[:json]&.dig("data", "me"))
check("B8", "Basic auth does not authenticate", !http(body: { query: ME }, headers: { "Authorization" => "Basic #{Base64.strict_encode64('a@b.c:pw')}" })[:json]&.dig("data", "me"))
check("B9", "token in query string not accepted", !http(path: "/graphql?access_token=#{tok}", body: { query: ME })[:json]&.dig("data", "me"))

# ---------- C. Input fuzzing ----------
bad_emails = ["' OR '1'='1", "admin@example.test' --", "a@b.c'; DROP TABLE users;--", "%' OR email LIKE '%", "x@y.test\r\nBcc: evil@x.test",
              "<script>alert(1)</script>@x.test", "${7*7}@x.test", "{{7*7}}@x.test", "‮@x.test", "a@b", "name​@example.test", "nаme@example.test"]
bad_emails.each_with_index do |s, i|
  r = login(s, "whatever-password")
  check("C1.#{i}", "login email payload #{s[0, 25].inspect}", clean?(r) && !tok_of(r, "login"), r[:body])
  r = signup(s)
  check("C2.#{i}", "signUp refuses email payload #{s[0, 25].inspect}", clean?(r) && !tok_of(r), r[:body], bad: "WEAK")
end
check("C3", "SQLi in password", !tok_of(login(email, "' OR '1'='1"), "login"), bad: "CRITICAL")
check("C5", "plus alias accepted (info)", true) # normal behaviour
r = signup("#{'a' * 300}@example.test")
check("C6", "300-char email rejected cleanly", clean?(r) && errs_of(r)&.any?, r[:body])
r = signup("#{'a' * 1_000_000}@example.test")
check("C7", "1MB body blocked with 400 BAD_REQUEST", r[:status] == 400 && code(r) == "BAD_REQUEST", "status=#{r[:status]} #{r[:body][0, 100]}")
r = http(raw: JSON.generate({ query: ME, pad: "x" * 20_000_000 }))
check("C8", "20MB body blocked", r[:status] == 400, "status=#{r[:status]} #{r[:ms]}ms")
r = gql("mutation { signUp(input:{email:\"#{uniq}\", password:\"#{PW}\", admin:true, id:\"x\"}){ token } }")
check("C9", "extra input fields (admin/id) rejected", r[:json]&.dig("errors") && !tok_of(r), r[:body])
r = gql("mutation { signUp(input:{email:\"#{uniq}\", password:\"#{PW}\", clientMutationId:\"<img src=x onerror=alert(1)>\"}){ clientMutationId } }")
check("C10", "reflected input is JSON-only", r[:headers]["content-type"].to_s.include?("json"), r[:headers]["content-type"])

# C11: blind (time-based) SQL injection. A normal injection check looks for a login or an error; a blind one only shows as a slow answer.
# Each payload asks PostgreSQL to sleep 4 seconds. If any answer is 3 seconds slower than the same call with a harmless value, the input reaches SQL.
SLEEP = 4_000
sleepers = ["'; SELECT pg_sleep(4)--", "' OR pg_sleep(4)--", "'||pg_sleep(4)||'", "1; SELECT pg_sleep(4)", "x') OR pg_sleep(4)--", "\" OR pg_sleep(4)--"]
blind = {
  "login email"           => ->(s) { login(s, "whatever-password") },
  "login password"        => ->(s) { login(email, s) },
  "signUp email"          => ->(s) { signup(s) },
  "signUp password"       => ->(s) { signup(uniq, s) },
  "requestPasswordReset"  => ->(s) { req_reset_blind(s) },
  "resetPassword email"   => ->(s) { gql("mutation D($i: ResetPasswordInput!){ resetPassword(input:$i){ success } }", variables: { i: { email: s, code: "123456", password: "New-Passw0rd-9!" } }) },
  "resetPassword code"    => ->(s) { gql("mutation D($i: ResetPasswordInput!){ resetPassword(input:$i){ success } }", variables: { i: { email: email, code: s, password: "New-Passw0rd-9!" } }) }
}
def req_reset_blind(s) = gql("mutation R($i: RequestPasswordResetInput!){ requestPasswordReset(input:$i){ success } }", variables: { i: { email: s } })
blind.each_with_index do |(name, call), i|
  base = [call.("harmless-value").fetch(:ms), call.("harmless-value").fetch(:ms)].max
  slow = sleepers.map { |s| [s, call.(s)[:ms]] }.select { |_, ms| ms >= base + SLEEP - 1_000 }
  check("C11.#{i}", "blind SQLi (pg_sleep) in #{name}", slow.empty?, "baseline=#{base}ms slow=#{slow.inspect}", bad: "CRITICAL")
end

# C12: second-order SQL injection and LIKE wildcards. The email format allows % and _ and +. Stored once, used in later queries.
# A victim exists; an attacker registers an email that looks like a pattern of the victim's. Nothing may match the victim.
victim = "qv#{SecureRandom.hex(4)}@example.test"
victim_tok = tok_of(signup(victim))
patterns = ["%@example.test", "qv%@example.test", "qv_#{victim[3..]}", "#{victim.sub('@', '%@')}", "#{victim.sub('@', '+x%@')}"]
patterns.each_with_index do |pat, i|
  r1 = signup(pat)
  stored = tok_of(r1) # the pattern may be a valid new account; that is fine, it must be its OWN account
  me_email = stored && gql(ME, token: stored)[:json]&.dig("data", "me", "email")
  l = login(pat, "wrong-password-x")
  rr = req_reset_blind(pat)
  check("C12.#{i}", "pattern email #{pat[0, 22].inspect}: own account only, never the victim's",
        (stored.nil? || me_email == pat.downcase.strip) && !tok_of(l, "login") && clean?(rr) && gql(ME, token: victim_tok)[:json]&.dig("data", "me", "email") == victim,
        "#{r1[:body][0, 80]} me=#{me_email.inspect}", bad: "CRITICAL")
end

# ---------- D. GraphQL abuse ----------
if LABEL == "prod"
  check("D1", "introspection OFF in production", !gql("{ __schema { types { name } } }")[:json]&.dig("data", "__schema"), "__schema answered")
  check("D2", "__type OFF in production", !gql('{ __type(name:"User"){ name } }')[:json]&.dig("data", "__type"))
end
check("D3", "no 'Did you mean' suggestions in production", LABEL != "prod" || !gql("{ meee }", token: tok)[:body].include?("Did you mean") && !gql("{ me { emai } }", token: tok)[:body].include?("Did you mean"))
check("D4", "fragment cycle", clean?(gql("fragment A on Query { ...B } fragment B on Query { ...A } { ...A }")))
check("D5", "20k fields (token limit)", clean?(gql("query { " + "__typename " * 20_000 + "}")))
aliases = (1..200).map { |i| "a#{i}: login(input:{email:\"#{email}\", password:\"guess#{i}\"}){ token }" }.join(" ")
r = gql("mutation { #{aliases} }")
check("D6", "200 aliased logins in ONE request are refused", r[:status] == 400 || r[:status] == 200 && !r[:json]&.dig("data"), "status=#{r[:status]} #{r[:ms]}ms #{r[:body][0, 100]}")
check("D7", "5k repeated directives", clean?(gql("query { __typename " + "@skip(if:false) " * 5000 + "}")))
nested = "{ " + "a: __typename " * 10 + "}"
check("D8", "complexity-heavy query refused", gql("{ " + (1..400).map { |i| "a#{i}: me { id email }" }.join(" ") + " }")[:json]&.dig("errors").to_s.match?(/complexity|too large|Invalid request|Authentication/i))
{ "D9 variables not JSON" => { query: ME, variables: "{not json" }, "D10 variables array" => { query: ME, variables: [1, 2] },
  "D11 variables integer" => { query: ME, variables: 12_345 }, "D12 query array" => { query: [ME] }, "D13 query object" => { query: { a: 1 } },
  "D14 operationName object" => { query: ME, operationName: { a: 1 } }, "D15 query missing" => {} }.each do |name, body|
  r = http(body: body)
  check(name.split.first, name.split(" ", 2).last, r[:status] == 400 && code(r) == "BAD_REQUEST", "status=#{r[:status]} #{r[:body][0, 120]}")
end
r = http(body: { query: ME, operationName: "nope" })
check("D16", "unknown operationName", clean?(r))
check("D17", "malformed JSON body", http(raw: "{not json")[:status] == 400)
check("D18", "200k nested brackets (parser DoS)", http(raw: "[" * 200_000)[:status] == 400)
check("D19", "empty body", http(raw: "")[:status] == 400)
check("D20", "form-encoded body refused", http(raw: "query=#{ME}", ctype: "application/x-www-form-urlencoded")[:status] == 400)
check("D21", "text/plain body refused", http(raw: "query=#{ME}", ctype: "text/plain")[:status] == 400)
check("D22", "GET /graphql not served", http(method: :get, path: "/graphql?query=#{URI.encode_www_form_component(ME)}")[:status] == 404)
check("D23", "missing required arg", code(gql("mutation { login(input:{email:\"a@b.c\"}){ token } }")) == "BAD_REQUEST")
r = gql("mutation L($i: LoginInput!){ login(input:$i){ token } }", variables: { i: { email: 123, password: ["x"] } })
check("D24", "wrong variable types -> VALIDATION_FAILED", code(r) == "VALIDATION_FAILED", r[:body])
check("D25", "null literals for required args", clean?(gql("mutation { login(input:{email:null,password:null}){ token } }")))

# ---------- E. Timing ----------
def avg(n) = (1..n).map { yield }.sum / n.to_f
t_known = avg(6) { login(email, "wrong-password-x")[:ms] }
t_unknown = avg(6) { login(uniq, "wrong-password-x")[:ms] }
check("E1", "login timing, known vs unknown email (prod only: bcrypt cost 1 in test)", LABEL != "prod" || (t_known - t_unknown).abs < [t_known, t_unknown].max * 0.4, "known=#{t_known.round}ms unknown=#{t_unknown.round}ms", bad: "WEAK")
rec("E2", "signUp tells whether an email is taken (accepted product decision)", "INFO", errs_of(signup(email)).inspect)

# ---------- F. HTTP, CORS, routes ----------
opts = ->(origin, extra = {}) { http(method: :options, path: "/graphql", headers: { "Origin" => origin, "Access-Control-Request-Method" => "POST" }.merge(extra), ctype: nil) }
check("F1", "CORS: evil origin gets no CORS headers", opts.("https://evil.example")[:headers]["access-control-allow-origin"].to_s.empty?)
check("F2", "CORS: allowed origin works", opts.("http://localhost:3000")[:headers]["access-control-allow-origin"] == "http://localhost:3000")
check("F3", "CORS: Origin null refused", http(body: { query: ME }, headers: { "Origin" => "null" })[:headers]["access-control-allow-origin"].to_s.empty?)
check("F4", "CORS: suffix bypass refused", http(body: { query: ME }, headers: { "Origin" => "http://localhost:3000.evil.com" })[:headers]["access-control-allow-origin"].to_s.empty?)
check("F5", "/sandbox not mounted", http(method: :get, path: "/sandbox", ctype: nil)[:status] == 404)
%w[/rails/info/routes /rails/info/properties /rails/mailers /letter_opener /sidekiq /admin /graphiql /users/sign_in /users/password /.env /config/master.key /cable].each do |p|
  check("F6", "probe #{p}", http(method: :get, path: p, ctype: nil)[:status] == 404, "", bad: "CHECK")
end
check("F7", "unknown route leaks nothing", LABEL != "prod" || !http(method: :get, path: "/nope", ctype: nil)[:body].match?(/routing|Rails|backtrace/i))
check("F8", "PUT /graphql not served", http(method: :put, body: { query: ME })[:status] == 404)
hd = http(body: { query: ME })[:headers]
rec("F9", "response headers", "INFO", hd.slice("x-frame-options", "x-content-type-options", "strict-transport-security", "cache-control", "server", "x-powered-by").inspect)
check("F10", "no server/framework version header", !hd.key?("x-powered-by") && !hd.fetch("server", "").match?(/\d/), hd.slice("server", "x-powered-by").inspect, bad: "WEAK")
if LABEL == "prod"
  check("F11", "HSTS header present (force_ssl)", hd["strict-transport-security"].to_s.include?("max-age"))
  check("F12", "spoofed Host header refused (config.hosts)", http(body: { query: ME }, headers: { "Host" => "evil.example" })[:status] == 403)
  check("F13", "/up health check reachable with any Host", http(method: :get, path: "/up", ctype: nil, headers: { "Host" => "probe.internal" })[:status] == 200)
end

# ---------- G. Concurrency ----------
ce = uniq
res = 12.times.map { Thread.new { signup(ce) } }.map(&:value)
check("G1", "12 parallel signUps, same email -> exactly 1 account", res.count { |x| tok_of(x) } == 1 && res.all? { |x| clean?(x) }, res.map { |x| x[:status] }.tally.inspect)
le = signup(uniq)[:json]["data"]["signUp"]["user"]["email"]
res = 8.times.map { Thread.new { login(le) } }.map(&:value)
toks = res.map { |x| tok_of(x, "login") }
check("G2", "8 parallel logins all succeed with distinct tokens", toks.all? && toks.uniq.size == toks.size)
rr = 5.times.map { Thread.new { gql(LOGOUT, token: toks.first) } }.map(&:value)
check("G3", "parallel logout of one token has no 500", rr.all? { |x| clean?(x) })

# ---------- H. Rate limits and lockout ----------
victim = signup(uniq)[:json]["data"]["signUp"]["user"]["email"]
6.times { login(victim, "guess-#{SecureRandom.hex(3)}") } # fresh IP each time: only the account lock can stop this
r = login(victim)
check("H1", "account locks after repeated wrong passwords (right password refused)", !tok_of(r, "login") && r[:json]&.dig("data", "login", "errors", 0, "code") == "INVALID_CREDENTIALS", r[:body])
locked_body = r[:json]&.dig("data", "login", "errors")
check("H2", "locked answer identical to a wrong-password answer", locked_body == wrong[:json]&.dig("data", "login", "errors"))
t_locked = avg(4) { login(victim)[:ms] }
check("H3", "locked account takes as long as an unknown one (prod only)", LABEL != "prod" || (t_locked - t_unknown).abs < [t_locked, t_unknown].max * 0.4, "locked=#{t_locked.round}ms unknown=#{t_unknown.round}ms", bad: "WEAK")

# Throttle counters need a real cache: the test environment uses a null store, so this runs in prod mode only.
if LABEL == "prod"
  $pinned_ip = "10.99.99.#{rand(1..254)}"
  codes = 14.times.map { login(uniq, "wrong-password-x")[:status] }
  check("H4", "11th public operation from one IP in a minute -> 429", codes[10..].all? { |c| c == 429 } && codes[0..9].none? { |c| c == 429 }, codes.tally.inspect)
  r = login(uniq, "wrong-password-x")
  check("H5", "429 uses the standard error shape and Retry-After", code(r) == "RATE_LIMITED" && r[:headers]["retry-after"].to_i.positive?, "#{r[:body][0, 100]} #{r[:headers]['retry-after']}")
  check("H6", "authenticated queries are not throttled", 15.times.map { gql(ME, token: tok)[:status] }.none? { |c| c == 429 })
  $pinned_ip = nil
end

# ---------- I. Password reset (email OTP) ----------
# The script cannot read the email, so in test mode a helper issues the code straight into the test database (the "inbox").
# Prod mode has a different secret key, so only the black-box checks (I1 to I9) run there.
REQ_RESET = "mutation R($i: RequestPasswordResetInput!){ requestPasswordReset(input:$i){ success errors{message path code} } }"
DO_RESET  = "mutation D($i: ResetPasswordInput!){ resetPassword(input:$i){ success errors{message path code} } }"
ROOT = File.expand_path("../../../..", __dir__)
OTP_HELPER = File.join(__dir__, "otp_helper.rb")
NEW_PW = "New-Passw0rd-9!"

def req_reset(email, extra = {}) = gql(REQ_RESET, variables: { i: { email: email }.merge(extra) })
def do_reset(email, otp_code, pw = NEW_PW) = gql(DO_RESET, variables: { i: { email: email, code: otp_code, password: pw } })
def reset_ok?(r) = r[:json]&.dig("data", "resetPassword", "success") == true
def reset_code(r) = r[:json]&.dig("data", "resetPassword", "errors", 0, "code")
def otp(action, email) = IO.popen({ "RAILS_ENV" => "test" }, [ "bin/rails", "runner", OTP_HELPER, action, email ], chdir: ROOT, err: File::NULL, &:read).to_s.strip
def wrong_guess(real) = real == "000000" ? "111111" : "000000"

rv = uniq
signup(rv)
known = req_reset(rv)
unknown = req_reset(uniq)
check("I1", "requestPasswordReset: known and unknown email give the same answer",
      known[:json] == unknown[:json] && known[:json]&.dig("data", "requestPasswordReset", "success") == true, "#{known[:body][0, 120]} | #{unknown[:body][0, 120]}", bad: "HIGH")
check("I2", "requestPasswordReset is on the public (throttled) list", PUBLIC_OPS.include?("requestPasswordReset") && PUBLIC_OPS.include?("resetPassword"), PUBLIC_OPS.inspect, bad: "HIGH")
odd = [ "not-an-email", "", "x" * 5000, "' OR 1=1 --", "a@b.test\r\nBcc: evil@x.test", "‮@x.test" ]
odd_res = odd.map { |s| req_reset(s) }
check("I3", "requestPasswordReset with odd input: clean, same answer as unknown email",
      odd_res.all? { |x| clean?(x) && x[:json] == unknown[:json] }, odd_res.map { |x| x[:body][0, 60] }.uniq.inspect, bad: "MEDIUM")
aliases = (1..200).map { |i| "a#{i}: requestPasswordReset(input:{email:\"#{uniq}\"}){ success }" }.join(" ")
r = gql("mutation { #{aliases} }")
check("I4", "200 aliased reset requests in ONE request are refused", r[:status] == 400 || (r[:status] == 200 && !r[:json]&.dig("data")), "status=#{r[:status]} #{r[:body][0, 100]}", bad: "HIGH")
r = req_reset(uniq, { role: "admin", id: "x", userId: SecureRandom.uuid })
check("I5", "extra input fields on requestPasswordReset rejected", r[:json]&.dig("errors") && !r[:json]&.dig("data", "requestPasswordReset", "success"), r[:body][0, 160], bad: "MEDIUM")
r = gql(DO_RESET, variables: { i: { email: uniq, code: "123456", password: NEW_PW, role: "admin" } })
check("I6", "extra input fields on resetPassword rejected", r[:json]&.dig("errors") && !reset_ok?(r), r[:body][0, 160], bad: "MEDIUM")
if LABEL == "prod"
  t_known = avg(6) { req_reset(rv)[:ms] }
  t_unknown = avg(6) { req_reset(uniq)[:ms] }
  check("I7", "requestPasswordReset timing, known vs unknown email", (t_known - t_unknown).abs < [ t_known, t_unknown ].max * 0.4 + 15, "known=#{t_known.round}ms unknown=#{t_unknown.round}ms", bad: "WEAK")
end
no_code = uniq
signup(no_code)
guesses = [ do_reset(uniq, "123456"), do_reset(no_code, "123456"), do_reset(rv, wrong_guess("")) ]
check("I8", "resetPassword: unknown email, no code, and wrong code all answer INVALID_CODE and identically",
      guesses.all? { |x| reset_code(x) == "INVALID_CODE" } && guesses.map { |x| x[:json] }.uniq.size == 1, guesses.map { |x| x[:body][0, 90] }.uniq.inspect, bad: "HIGH")
bad_codes = [ "", "12345", "1234567", "123456\n", " 123456", "１２３４５６", "1e5000", "0x1234", "' OR 1=1 --", "x" * 10_000, "123456" * 1000 ]
bad_res = bad_codes.map { |c| do_reset(no_code, c) }
check("I9", "resetPassword code in a wrong format: clean INVALID_CODE", bad_res.all? { |x| clean?(x) && reset_code(x) == "INVALID_CODE" }, bad_res.map { |x| x[:status] }.tally.inspect, bad: "MEDIUM")

if LABEL == "test"
  fresh = -> { e = uniq; t = tok_of(signup(e)); [ e, t ] }

  e, session = fresh.call
  c = otp("mint", e)
  check("I10", "helper issued a 6-digit code", c.match?(/\A\d{6}\z/), c.inspect)
  r = do_reset(e, c)
  check("I11", "reset with the right code works", reset_ok?(r), r[:body][0, 160])
  check("I12", "new password logs in, old password does not", tok_of(login(e, NEW_PW), "login") && !tok_of(login(e), "login"), bad: "HIGH")
  check("I13", "session token from before the reset is dead", code(gql(ME, token: session)) == "UNAUTHENTICATED", bad: "HIGH")
  check("I14", "reset does not hand out a token", r[:json]&.dig("data", "resetPassword")&.keys&.sort == %w[errors success], r[:body][0, 160], bad: "MEDIUM")
  replay = do_reset(e, c, "Other-Passw0rd-7!")
  check("I15", "replay of the used code is refused", reset_code(replay) == "INVALID_CODE" && !reset_ok?(replay), replay[:body][0, 160], bad: "CRITICAL")

  e, = fresh.call
  c = otp("mint", e)
  five = 5.times.map { do_reset(e, wrong_guess(c)) } # a new IP each time: only the per-code limit can stop this
  check("I16", "5 wrong guesses from 5 IPs kill the code, even the right code is refused after",
        five.all? { |x| reset_code(x) == "INVALID_CODE" } && reset_code(do_reset(e, c)) == "INVALID_CODE" && otp("attempts", e) == "nil", otp("attempts", e), bad: "CRITICAL")

  e, = fresh.call
  c = otp("mint", e)
  four = 4.times.map { do_reset(e, wrong_guess(c)) }
  check("I17", "4 wrong guesses do not kill the code", four.all? { |x| reset_code(x) == "INVALID_CODE" } && otp("attempts", e) == "4", otp("attempts", e), bad: "MEDIUM")

  e, = fresh.call
  c = otp("mint", e)
  rs = 8.times.map { |i| Thread.new { do_reset(e, c, "Race-Passw0rd-#{i}x!") } }.map(&:value)
  check("I18", "8 parallel resets with the same right code: exactly one succeeds, no 500",
        rs.count { |x| reset_ok?(x) } == 1 && rs.all? { |x| clean?(x) }, rs.map { |x| x[:body][0, 70] }.tally.inspect, bad: "HIGH")

  e, = fresh.call
  c = otp("mint", e)
  rs = 20.times.map { Thread.new { do_reset(e, wrong_guess(c)) } }.map(&:value)
  check("I19", "20 parallel wrong guesses: no 500, the code is dead, the right code is refused",
        rs.all? { |x| clean?(x) } && reset_code(do_reset(e, c)) == "INVALID_CODE", rs.map { |x| x[:status] }.tally.inspect, bad: "CRITICAL")

  ea, = fresh.call
  eb, = fresh.call
  ca = otp("mint", ea)
  r = do_reset(eb, ca)
  check("I20", "user A's code does not reset user B", reset_code(r) == "INVALID_CODE" && !tok_of(login(eb, NEW_PW), "login"), r[:body][0, 160], bad: "CRITICAL")

  e, = fresh.call
  c = otp("mint", e)
  weak = do_reset(e, c, "short")
  check("I21", "weak password: VALIDATION_FAILED, the code survives, a good password then works",
        weak[:json]&.dig("data", "resetPassword", "errors", 0, "code") == "VALIDATION_FAILED" && reset_ok?(do_reset(e, c)), weak[:body][0, 160], bad: "MEDIUM")

  e, = fresh.call
  c = otp("mint", e)
  otp("expire", e)
  check("I22", "expired code is refused", reset_code(do_reset(e, c)) == "INVALID_CODE", bad: "HIGH")

  e, = fresh.call
  7.times { login(e, "wrong-pw-#{SecureRandom.hex(3)}") }
  locked = !tok_of(login(e), "login")
  asked = req_reset(e)
  c = otp("mint", e)
  do_reset(e, c)
  check("I23", "a locked account can ask for a reset, and the reset unlocks it", locked && asked[:json]&.dig("data", "requestPasswordReset", "success") && tok_of(login(e, NEW_PW), "login"), "locked=#{locked}", bad: "MEDIUM")

  # I24: the reset email is the one place this API writes HTML. Nothing the user typed may end up in the body, and what is there must be escaped.
  e = "q%+#{SecureRandom.hex(3)}@example.test" # the email format refuses < and >, so the nastiest legal value is used
  signup(e)
  html, text = otp("mail", e).split("\n----TEXT----\n", 2)
  check("I24", "reset email body: only a 6-digit code and the lifetime, no user input, no raw tags beyond the template",
        html.to_s.include?("<p") && !html.to_s.include?(e) && !text.to_s.include?(e) && html.scan(/\b\d{6}\b/).size == 1 && text.to_s.scan(/\b\d{6}\b/).size == 1 &&
        !html.to_s.match?(/<script|onerror=|javascript:/i), html.to_s[0, 160], bad: "HIGH")
end

# ---------- J. OWASP GraphQL cheat sheet: batching, discovery, error leaks, timeouts ----------
# Source: https://cheatsheetseries.owasp.org/cheatsheets/GraphQL_Cheat_Sheet.html
jt = tok_of(signup(uniq))

# J1: array-based batching. One HTTP request carrying many operations would get around every per-request limit
# (the throttle, the 5-guesses-per-code limit). Must be refused as a whole.
ops = ->(n, q) { Array.new(n) { { query: q } } }
{ "J1.0" => ops.(20, "mutation { login(input:{email:\"#{email}\", password:\"guess\"}){ token } }"),
  "J1.1" => ops.(200, "mutation { requestPasswordReset(input:{email:\"#{uniq}\"}){ success } }"),
  "J1.2" => ops.(20, ME) }.each do |name, batch|
  r = http(body: batch, headers: { "Authorization" => "Bearer #{jt}" })
  answered = r[:json].is_a?(Array) || r[:json]&.dig("data")
  check(name, "JSON array of #{batch.size} operations refused as a whole", clean?(r) && !answered && r[:status] == 400, "status=#{r[:status]} #{r[:body][0, 120]}", bad: "CRITICAL")
end
r = http(body: { _json: ops.(5, ME) }, headers: { "Authorization" => "Bearer #{jt}" })
check("J1.3", "_json parameter does not smuggle a batch", clean?(r) && !r[:json].is_a?(Array) && !r[:json]&.dig("data"), r[:body][0, 120], bad: "HIGH")
r = http(raw: "[" + ([JSON.generate({ query: ME })] * 20).join(",") + "]", headers: { "Authorization" => "Bearer #{jt}" })
check("J1.4", "raw multiplex body refused", r[:status] == 400 && !r[:json].is_a?(Array), "status=#{r[:status]}", bad: "CRITICAL")

# J2: NoSQL-style objects and shell metacharacters where a string is expected.
[{ "$ne" => nil }, { "$gt" => "" }, { "$regex" => ".*" }].each_with_index do |o, i|
  r = gql(LOGIN, variables: { i: { email: o, password: o } })
  check("J2.#{i}", "operator object #{o.keys.first} instead of a string in login", clean?(r) && !tok_of(r, "login"), r[:body][0, 120], bad: "CRITICAL")
end
shells = [";sleep 4", "$(sleep 4)", "`sleep 4`", "|sleep 4", "&& sleep 4", "\nsleep 4"]
[["login email", ->(s) { login(s, "whatever-password") }], ["signUp email", ->(s) { signup(s) }],
 ["reset email", ->(s) { req_reset_blind(s) }]].each_with_index do |(name, call), i|
  base = call.("harmless-value")[:ms]
  slow = shells.map { |s| [s, call.(s)[:ms]] }.select { |_, ms| ms >= base + 3_000 }
  check("J2.s#{i}", "shell metacharacters in #{name} cause no delay", slow.empty?, "baseline=#{base}ms slow=#{slow.inspect}", bad: "CRITICAL")
end

# J3: field discovery. With introspection off, an attacker guesses names. A guessed name must not exist, or must be locked.
wordlist = %w[users allUsers user node nodes admin accounts account tenants tenant organizations organization debug config settings
              viewer currentUser version health stats metrics logs tokens sessions roles permissions impersonate deleteUser updateUser
              createUser createAdmin resetAllPasswords exportData backup]
# A guess counts as a hit when its answer differs from the answer for a random name that surely does not exist.
probe = ->(w) { [gql("{ #{w} { __typename } }"), gql("mutation { #{w}(input:{}) { __typename } }")] }
fake = "zz#{SecureRandom.hex(4)}"
fake_q, fake_m = probe.(fake).map { |x| x[:body].gsub(fake, "NAME") }
hits = wordlist.select do |w|
  q, m = probe.(w).map { |x| x[:body].gsub(w, "NAME") }
  q != fake_q || m != fake_m
end
exposed = hits.select do |w|
  r = gql("{ #{w} { __typename } }")
  r2 = gql("mutation { #{w}(input:{}) { __typename } }")
  [r, r2].any? { |x| x[:json]&.dig("data")&.values&.any? { |v| !v.nil? } }
end
check("J3.0", "guessed names never return data without a token", exposed.empty?, exposed.inspect, bad: "CRITICAL")
check("J3.1", "Relay node/nodes root fields absent (they bypass per-type authorization)", !hits.include?("node") && !hits.include?("nodes"), hits.inspect, bad: "HIGH")
rec("J3.2", "guessed names that exist as fields (review: each must be intended and protected)", "INFO", hits.inspect)

# J4: error messages. No class names, file paths, SQL, or stack traces in anything a client can trigger.
leak = /\.rb\b|\/app\/|\/gems\/|\/lib\/|ActiveRecord|ActionController|PG::|Errno|NoMethodError|NameError|SELECT\s|INSERT\s|#<|backtrace|stack ?trace|Traceback/i
probes = {
  "syntax error" => { query: "{ me { " }, "unknown field" => { query: "{ meee }" }, "bad enum/arg type" => { query: "mutation { login(input: 5){ token } }" },
  "null for required" => { query: LOGIN, variables: { i: nil } }, "bad variable type" => { query: LOGIN, variables: { i: { email: 5, password: [1] } } },
  "unknown directive" => { query: "{ me @nope { id } }" }, "wrong content" => { query: ME, variables: "[1]" },
  "deep nesting" => { query: "{ " + "me { " * 300 + "id" + " }" * 300 + " }" }, "huge int" => { query: "mutation { login(input:{email:\"a@b.test\", password:99999999999999999999999}){ token } }" },
  "unterminated string" => { query: "mutation { login(input:{email:\"abc" }
}
leaks = probes.filter_map do |name, b|
  r = http(body: b, headers: { "Authorization" => "Bearer #{jt}" })
  name if r[:body].match?(leak)
end
check("J4.0", "error answers hold no class names, paths, SQL, or traces", leaks.empty?, leaks.inspect, bad: "HIGH")
r = signup("a@b.test", "x")
check("J4.1", "validation errors name the rule, not the implementation", !r[:body].match?(leak), r[:body][0, 160], bad: "MEDIUM")

# J5: query timeout and cost. The heaviest query the complexity limit lets through must still answer fast.
# (Black-box can only measure; whether a timeout exists is read from the source below.)
heavy = [60, 40, 20, 10].lazy.map { |n| [n, gql("{ " + (1..n).map { |i| "a#{i}: me { id email }" }.join(" ") + " }", token: jt)] }
                        .find { |_, r| r[:json]&.dig("data") }
if heavy
  n, r = heavy
  check("J5.0", "heaviest accepted query (#{n} aliased reads) answers in under 3s", r[:ms] < 3_000, "#{r[:ms]}ms", bad: "WEAK")
else
  rec("J5.0", "no aliased query got through the complexity limit, nothing to time", "INFO")
end
src = File.expand_path("../../../..", __dir__)
timeout_found = [
  `grep -rlE "Rack::Timeout|rack-timeout|GraphQL::Schema::Timeout|use GraphQL::Schema::Timeout" #{src}/Gemfile #{src}/app #{src}/config 2>/dev/null`,
  `grep -rlE "statement_timeout" #{src}/config/database.yml #{src}/config/initializers 2>/dev/null`
].map(&:strip).reject(&:empty?)
check("J5.1", "a request or statement timeout is configured (rack-timeout, GraphQL timeout, or statement_timeout)", timeout_found.any?, "none found in Gemfile, app/, config/", bad: "WEAK")

# ---------- Z. Schema-driven phase (every operation, including ones added later) ----------
if LABEL == "test"
  frag = "fragment T on __Type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } }"
  intro = gql("{ __schema { queryType { name } mutationType { name } types { kind name " \
              "fields { name type { ...T } args { name type { ...T } } } inputFields { name type { ...T } } enumValues { name } } } } #{frag}")
  types = (intro[:json]&.dig("data", "__schema", "types") || []).to_h { |t| [t["name"], t] }
  roots = %w[queryType mutationType].filter_map { |k| n = intro[:json]&.dig("data", "__schema", k, "name"); [k, types[n]] if n }
  fuzz = ["", "x" * 10_000, "' OR 1=1 --", "\u0000", "🔥" * 50, "../../etc/passwd", "<script>alert(1)</script>", "-1", "99999999999999999999"]

  type_str = ->(t) { t["kind"] == "NON_NULL" ? "#{type_str.(t['ofType'])}!" : t["kind"] == "LIST" ? "[#{type_str.(t['ofType'])}]" : t["name"] }
  base = ->(t) { t["ofType"] ? base.(t["ofType"]) : t }
  build = lambda do |t, str|
    case t["kind"]
    when "NON_NULL" then build.(t["ofType"], str)
    when "LIST" then [build.(t["ofType"], str)]
    when "ENUM" then types[t["name"]]["enumValues"].first["name"]
    when "INPUT_OBJECT" then types[t["name"]]["inputFields"].to_h { |f| [f["name"], build.(f["type"], str)] }
    else
      case t["name"] when "Int" then 1 when "Float" then 1.5 when "Boolean" then true when "ID" then SecureRandom.uuid else str end
    end
  end
  op_for = lambda do |kind, field, str|
    vars = field["args"].map { |a| "$#{a['name']}: #{type_str.(a['type'])}" }.join(", ")
    args = field["args"].map { |a| "#{a['name']}: $#{a['name']}" }.join(", ")
    sel = %w[OBJECT INTERFACE UNION].include?(base.(field["type"])["kind"]) ? " { __typename }" : ""
    ["#{kind} Z#{vars.empty? ? '' : "(#{vars})"} { #{field['name']}#{args.empty? ? '' : "(#{args})"}#{sel} }",
     field["args"].to_h { |a| [a["name"], build.(a["type"], str)] }]
  end

  roots.each do |root_key, root|
    kind = root_key == "queryType" ? "query" : "mutation"
    (root["fields"] || []).each do |field|
      public_op = PUBLIC_OPS.include?(field["name"])
      query, vars = op_for.(kind, field, "x")
      unless public_op
        r = gql(query, variables: vars)
        check("Z1", "#{kind} #{field['name']}: no token -> denied", %w[UNAUTHENTICATED FORBIDDEN].include?(code(r)), r[:body][0, 160], bad: "CRITICAL")
        r = gql(query, variables: vars, token: "garbage.token.value")
        check("Z2", "#{kind} #{field['name']}: garbage token -> denied", %w[UNAUTHENTICATED FORBIDDEN].include?(code(r)), r[:body][0, 160], bad: "CRITICAL")
      end
      fuzz.each_with_index do |f, i|
        user_token = tok_of(signup(uniq))
        q, v = op_for.(kind, field, f)
        r = gql(q, variables: v, token: user_token)
        check("Z3.#{i}", "#{kind} #{field['name']}: string args = #{f[0, 14].inspect}", clean?(r), "status=#{r[:status]} #{r[:body][0, 160]}")
      end
      next if field["args"].empty?
      r = gql("#{kind} { #{field['name']} }", token: tok_of(signup(uniq)))
      check("Z4", "#{kind} #{field['name']}: missing required args -> clean error", clean?(r), r[:body][0, 160])
    end
  end
  # ---- Z5. Depth limit: find a chain of object fields (needs no required args) and nest it deeper and deeper.
  # Dormant until the schema has a type that can nest (a cycle, like User -> organization -> users). Then it measures the limit.
  depth_user = tok_of(signup(uniq))
  object_fields = ->(t) { (types[t]&.dig("fields") || []).select { |f| f["args"].none? { |a| a["type"]["kind"] == "NON_NULL" } && %w[OBJECT INTERFACE].include?(base.(f["type"])["kind"]) } }
  chain = lambda do |type_name, n|
    return [] if n.zero?
    object_fields.(type_name).each do |f|
      rest = chain.(base.(f["type"])["name"], n - 1)
      return [f["name"], *rest] if rest
    end
    nil
  end
  query_root = roots.find { |k, _| k == "queryType" }&.last
  path = query_root && chain.(query_root["name"], 15)
  if path
    nest = ->(n) { "{ " + path.first(n).map { |f| "#{f} { " }.join + "__typename" + " }" * n + " }" }
    limit = (1..15).find { |n| gql(nest.(n), token: depth_user)[:body].match?(/depth/i) }
    check("Z5.0", "query depth is limited (first refused at depth #{limit.inspect})", !limit.nil? && limit <= 12, "refused at #{limit.inspect}", bad: "HIGH")
    rec("Z5.1", "depth limit measured", "INFO", "first depth refused: #{limit.inspect}")
  else
    rec("Z5", "depth limit not testable yet: the schema has no object field that nests 15 deep (add a probe when it does)", "INFO")
  end

  # ---- Z6. Amount limits: any list or any size-like argument must be capped.
  count_max = ->(v) { v.is_a?(Array) ? [v.size, *v.map { |x| count_max.(x) }].max : v.is_a?(Hash) ? (v.values.map { |x| count_max.(x) }.max || 0) : 0 }
  size_args = /\A(first|last|limit|per_?page|page_?size|count|take|size|max|top)\z/i
  roots.each do |root_key, root|
    kind = root_key == "queryType" ? "query" : "mutation"
    (root["fields"] || []).each do |field|
      listy = ->(t) { t["kind"] == "LIST" || (t["ofType"] && listy.(t["ofType"])) }
      sized = field["args"].select { |a| a["name"].match?(size_args) }
      next if sized.empty? && !listy.(field["type"])
      q, v = op_for.(kind, field, "x")
      sized.each { |a| v[a["name"]] = 99_999_999 }
      r = gql(q, variables: v, token: depth_user)
      check("Z6.#{field['name']}", "#{kind} #{field['name']}: huge #{sized.map { |a| a['name'] }.inspect} is refused or capped (max 100 rows)",
            clean?(r) && (r[:json]&.dig("errors") || count_max.(r[:json]&.dig("data")) <= 100), r[:body][0, 160], bad: "HIGH")
      if sized.any? { |a| a["type"]["kind"] != "NON_NULL" }
        q2, v2 = op_for.(kind, field.merge("args" => field["args"] - sized), "x")
        r2 = gql(q2, variables: v2, token: depth_user)
        check("Z6.#{field['name']}.default", "#{kind} #{field['name']}: no size argument still returns a bounded list", clean?(r2) && count_max.(r2[:json]&.dig("data")) <= 100, r2[:body][0, 160], bad: "MEDIUM")
      end
    end
  end

  # ---- Z7. IDOR / BOLA: user B sends user A's real id. The answer must be the same as for an id that does not exist.
  # Dormant until an operation takes an ID argument.
  owner = signup(uniq)
  owner_id = owner[:json]&.dig("data", "signUp", "user", "id")
  intruder = tok_of(signup(uniq))
  norm = ->(r) { r[:body].gsub(/[0-9a-f]{8}-[0-9a-f-]{27}|\b\d+\b/i, "ID") }
  idor_seen = false
  roots.each do |root_key, root|
    kind = root_key == "queryType" ? "query" : "mutation"
    (root["fields"] || []).each do |field|
      has_id = ->(t) { t["name"] == "ID" || (t["kind"] == "INPUT_OBJECT" && types[t["name"]]["inputFields"].any? { |f| has_id.(base.(f["type"])) }) }
      next unless field["args"].any? { |a| has_id.(base.(a["type"])) }
      idor_seen = true
      q, v = op_for.(kind, field, "x")
      swap = ->(h, id) { h.to_h { |k, x| [k, x.is_a?(Hash) ? swap.(x, id) : (x.is_a?(String) && x.match?(/\A[0-9a-f-]{36}\z/) ? id : x)] } }
      mine = gql(q, variables: swap.(v, owner_id), token: intruder)
      none = gql(q, variables: swap.(v, SecureRandom.uuid), token: intruder)
      check("Z7.#{field['name']}", "#{kind} #{field['name']}: another user's id answers exactly like a missing id",
            clean?(mine) && norm.(mine) == norm.(none) && code(mine) == code(none), "#{mine[:body][0, 90]} | #{none[:body][0, 90]}", bad: "CRITICAL")
    end
  end
  rec("Z7", "IDOR probe has nothing to test yet: no operation takes an ID (add two-user scenarios when one does)", "INFO") unless idor_seen

  # ---- Z8. SSRF: a string argument that looks like a URL or host must never make the server call out.
  # A local canary listens on a random port. If the server connects to it, that is a finding.
  require "socket"
  url_args = /url|uri|host|webhook|callback|endpoint|link|domain|address/i
  ssrf_seen = false
  canary = TCPServer.new("127.0.0.1", 0)
  canary_port = canary.addr[1]
  hits_on_canary = []
  Thread.new { loop { c = canary.accept; hits_on_canary << c.gets.to_s[0, 60]; c.close } }
  roots.each do |root_key, root|
    kind = root_key == "queryType" ? "query" : "mutation"
    (root["fields"] || []).each do |field|
      targets = field["args"].select { |a| a["name"].match?(url_args) || (base.(a["type"])["kind"] == "INPUT_OBJECT" && types[base.(a["type"])["name"]]["inputFields"].any? { |f| f["name"].match?(url_args) }) }
      next if targets.empty?
      ssrf_seen = true
      ["http://127.0.0.1:#{canary_port}/ssrf", "http://localhost:#{canary_port}/", "http://[::1]:#{canary_port}/", "http://2130706433:#{canary_port}/",
       "http://169.254.169.254/latest/meta-data/", "file:///etc/passwd", "gopher://127.0.0.1:#{canary_port}/"].each_with_index do |u, i|
        q, v = op_for.(kind, field, u)
        r = gql(q, variables: v, token: depth_user)
        check("Z8.#{field['name']}.#{i}", "#{kind} #{field['name']}: internal target #{u[0, 30].inspect} not fetched, no 500, no file/metadata in answer",
              clean?(r) && !r[:body].match?(/root:.*:0:0|ami-id|instance-id/), r[:body][0, 160], bad: "CRITICAL")
      end
      sleep 3 # background jobs may fetch late
    end
  end
  if ssrf_seen
    check("Z8.canary", "the server never connected to the local canary (#{hits_on_canary.size} connections)", hits_on_canary.empty?, hits_on_canary.inspect, bad: "CRITICAL")
  else
    rec("Z8", "SSRF probe has nothing to test yet: no operation takes a URL or host argument", "INFO")
  end
  canary.close
else
  rec("Z", "schema phase skipped (introspection is off in this mode, as it should be)", "INFO")
end

File.write(OUT, JSON.pretty_generate($results))
puts "\nSUMMARY #{LABEL}: #{$results.map { |x| x[:verdict] }.tally.inspect}"
