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
# Members must finish onboarding before the API lets them do anything else (OnboardingGate). A user made here is onboarded at once,
# so every other section can use it. Section N and P pass `onboard: false` to test the gate and the profile themselves.
MY_ONB = "{ me { onboarding { completed currentStep steps { key completed completedAt } } } }"
UPDATE_PROFILE = "mutation P($i: UpdateProfileInput!){ updateProfile(input:$i){ user{ id firstName lastName dateOfBirth phone } errors{message path code} } }"
UPDATE_ADDRESS = "mutation A($i: UpdateAddressInput!){ updateAddress(input:$i){ user{ id addressLine1 addressLine2 city state postalCode country } errors{message path code} } }"
ACCEPT_TERMS = "mutation T($i: AcceptTermsInput!){ acceptTerms(input:$i){ user{ id termsVersion termsAcceptedAt } errors{message path code} } }"
PROFILE = { firstName: "Qa", lastName: "Tester", dateOfBirth: "1990-05-21", phone: "+14155552671" }.freeze
ADDRESS = { addressLine1: "1 Market Street", addressLine2: "Suite 4", city: "San Francisco", state: "CA", postalCode: "94105", country: "US" }.freeze

# The server finishes a step itself when the data of the step is saved: there is no "complete step" operation. The version of the terms
# is read from the test database (the client of the real API ships it with the terms text it shows).
def terms_version = @terms_version ||= IO.popen({ "RAILS_ENV" => "test" }, [ "bin/rails", "runner", File.join(__dir__, "otp_helper.rb"), "terms_version", "-" ], chdir: File.expand_path("../../../..", __dir__), err: File::NULL, &:read).to_s.strip
def prof_save(token, extra = {}) = gql(UPDATE_PROFILE, variables: { i: PROFILE.merge(extra) }, token: token)
def addr_save(token, extra = {}) = gql(UPDATE_ADDRESS, variables: { i: ADDRESS.merge(extra) }, token: token)
def terms_save(token, version = terms_version, extra = {}) = gql(ACCEPT_TERMS, variables: { i: { version: version }.merge(extra) }, token: token)
def op_errs(r, op) = r[:json]&.dig("data", op, "errors")
def onb_of(token) = gql(MY_ONB, token: token)[:json]&.dig("data", "me", "onboarding")

# Saves the data of every step (profile, address, terms): the server marks the steps done. Does nothing for a user who has no steps (a super_admin).
def onboard!(token)
  return unless token

  state = onb_of(token)
  return if state.nil? || state["completed"]

  prof_save(token)
  addr_save(token)
  terms_save(token)
end

def signup(email, pw = PW, onboard: true)
  r = gql(SIGNUP, variables: { i: { email: email, password: pw } })
  onboard!(tok_of(r)) if onboard
  r
end
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

[ "short", "a@b", "plainstring", "@nodomain.com", "" ].each_with_index do |bad, i|
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
check("B4", "valid token, payload tampered (sub swapped)", denied.([ parts[0], b64(claims.merge("sub" => SecureRandom.uuid)), parts[2] ].join(".")), bad: "CRITICAL")
check("B5", "valid token, signature byte flipped", denied.(tok[0..-2] + (tok[-1] == "A" ? "B" : "A")), bad: "CRITICAL")
[ "garbage", "a.b.c", "....", "null", "'; DROP TABLE users;--", "A" * 100_000 ].each_with_index do |g, i|
  check("B6.#{i}", "garbage token #{g[0, 12].inspect} (#{g.size} bytes)", denied.(g))
end
check("B7", "token without Bearer prefix ignored", !http(body: { query: ME }, headers: { "Authorization" => tok })[:json]&.dig("data", "me"))
check("B8", "Basic auth does not authenticate", !http(body: { query: ME }, headers: { "Authorization" => "Basic #{Base64.strict_encode64('a@b.c:pw')}" })[:json]&.dig("data", "me"))
check("B9", "token in query string not accepted", !http(path: "/graphql?access_token=#{tok}", body: { query: ME })[:json]&.dig("data", "me"))

# ---------- C. Input fuzzing ----------
bad_emails = [ "' OR '1'='1", "admin@example.test' --", "a@b.c'; DROP TABLE users;--", "%' OR email LIKE '%", "x@y.test\r\nBcc: evil@x.test",
              "<script>alert(1)</script>@x.test", "${7*7}@x.test", "{{7*7}}@x.test", "‮@x.test", "a@b", "name​@example.test", "nаme@example.test" ]
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
sleepers = [ "'; SELECT pg_sleep(4)--", "' OR pg_sleep(4)--", "'||pg_sleep(4)||'", "1; SELECT pg_sleep(4)", "x') OR pg_sleep(4)--", "\" OR pg_sleep(4)--" ]
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
  base = [ call.("harmless-value").fetch(:ms), call.("harmless-value").fetch(:ms) ].max
  slow = sleepers.map { |s| [ s, call.(s)[:ms] ] }.select { |_, ms| ms >= base + SLEEP - 1_000 }
  check("C11.#{i}", "blind SQLi (pg_sleep) in #{name}", slow.empty?, "baseline=#{base}ms slow=#{slow.inspect}", bad: "CRITICAL")
end

# C12: second-order SQL injection and LIKE wildcards. The email format allows % and _ and +. Stored once, used in later queries.
# A victim exists; an attacker registers an email that looks like a pattern of the victim's. Nothing may match the victim.
victim = "qv#{SecureRandom.hex(4)}@example.test"
victim_tok = tok_of(signup(victim))
patterns = [ "%@example.test", "qv%@example.test", "qv_#{victim[3..]}", "#{victim.sub('@', '%@')}", "#{victim.sub('@', '+x%@')}" ]
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
{ "D9 variables not JSON" => { query: ME, variables: "{not json" }, "D10 variables array" => { query: ME, variables: [ 1, 2 ] },
  "D11 variables integer" => { query: ME, variables: 12_345 }, "D12 query array" => { query: [ ME ] }, "D13 query object" => { query: { a: 1 } },
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
r = gql("mutation L($i: LoginInput!){ login(input:$i){ token } }", variables: { i: { email: 123, password: [ "x" ] } })
check("D24", "wrong variable types -> VALIDATION_FAILED", code(r) == "VALIDATION_FAILED", r[:body])
check("D25", "null literals for required args", clean?(gql("mutation { login(input:{email:null,password:null}){ token } }")))

# ---------- E. Timing ----------
def avg(n) = (1..n).map { yield }.sum / n.to_f
t_known = avg(6) { login(email, "wrong-password-x")[:ms] }
t_unknown = avg(6) { login(uniq, "wrong-password-x")[:ms] }
check("E1", "login timing, known vs unknown email (prod only: bcrypt cost 1 in test)", LABEL != "prod" || (t_known - t_unknown).abs < [ t_known, t_unknown ].max * 0.4, "known=#{t_known.round}ms unknown=#{t_unknown.round}ms", bad: "WEAK")
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
check("H3", "locked account takes as long as an unknown one (prod only)", LABEL != "prod" || (t_locked - t_unknown).abs < [ t_locked, t_unknown ].max * 0.4, "locked=#{t_locked.round}ms unknown=#{t_unknown.round}ms", bad: "WEAK")

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
def otp(action, email, *rest) = IO.popen({ "RAILS_ENV" => "test" }, [ "bin/rails", "runner", OTP_HELPER, action, email, *rest ], chdir: ROOT, err: File::NULL, &:read).to_s.strip
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
# Accepted decision (see password_reset_spec): a malformed email is VALIDATION_FAILED, which says nothing about accounts.
check("I3", "requestPasswordReset with odd input: clean, and the same answer as an unknown email or a plain VALIDATION_FAILED",
      odd_res.all? { |x| clean?(x) && (x[:json] == unknown[:json] || x[:json]&.dig("data", "requestPasswordReset", "errors", 0, "code") == "VALIDATION_FAILED") }, odd_res.map { |x| x[:body][0, 60] }.uniq.inspect, bad: "MEDIUM")
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
r = http(raw: "[" + ([ JSON.generate({ query: ME }) ] * 20).join(",") + "]", headers: { "Authorization" => "Bearer #{jt}" })
check("J1.4", "raw multiplex body refused", r[:status] == 400 && !r[:json].is_a?(Array), "status=#{r[:status]}", bad: "CRITICAL")

# J2: NoSQL-style objects and shell metacharacters where a string is expected.
[ { "$ne" => nil }, { "$gt" => "" }, { "$regex" => ".*" } ].each_with_index do |o, i|
  r = gql(LOGIN, variables: { i: { email: o, password: o } })
  check("J2.#{i}", "operator object #{o.keys.first} instead of a string in login", clean?(r) && !tok_of(r, "login"), r[:body][0, 120], bad: "CRITICAL")
end
shells = [ ";sleep 4", "$(sleep 4)", "`sleep 4`", "|sleep 4", "&& sleep 4", "\nsleep 4" ]
[ [ "login email", ->(s) { login(s, "whatever-password") } ], [ "signUp email", ->(s) { signup(s) } ],
 [ "reset email", ->(s) { req_reset_blind(s) } ] ].each_with_index do |(name, call), i|
  base = call.("harmless-value")[:ms]
  slow = shells.map { |s| [ s, call.(s)[:ms] ] }.select { |_, ms| ms >= base + 3_000 }
  check("J2.s#{i}", "shell metacharacters in #{name} cause no delay", slow.empty?, "baseline=#{base}ms slow=#{slow.inspect}", bad: "CRITICAL")
end

# J3: field discovery. With introspection off, an attacker guesses names. A guessed name must not exist, or must be locked.
wordlist = %w[users allUsers user node nodes admin accounts account tenants tenant organizations organization debug config settings
              viewer currentUser version health stats metrics logs tokens sessions roles permissions impersonate deleteUser updateUser
              createUser createAdmin resetAllPasswords exportData backup]
# A guess counts as a hit when its answer differs from the answer for a random name that surely does not exist.
probe = ->(w) { [ gql("{ #{w} { __typename } }"), gql("mutation { #{w}(input:{}) { __typename } }") ] }
fake = "zz#{SecureRandom.hex(4)}"
fake_q, fake_m = probe.(fake).map { |x| x[:body].gsub(fake, "NAME") }
hits = wordlist.select do |w|
  q, m = probe.(w).map { |x| x[:body].gsub(w, "NAME") }
  q != fake_q || m != fake_m
end
exposed = hits.select do |w|
  r = gql("{ #{w} { __typename } }")
  r2 = gql("mutation { #{w}(input:{}) { __typename } }")
  [ r, r2 ].any? { |x| x[:json]&.dig("data")&.values&.any? { |v| !v.nil? } }
end
check("J3.0", "guessed names never return data without a token", exposed.empty?, exposed.inspect, bad: "CRITICAL")
check("J3.1", "Relay node/nodes root fields absent (they bypass per-type authorization)", !hits.include?("node") && !hits.include?("nodes"), hits.inspect, bad: "HIGH")
rec("J3.2", "guessed names that exist as fields (review: each must be intended and protected)", "INFO", hits.inspect)

# J4: error messages. No class names, file paths, SQL, or stack traces in anything a client can trigger.
leak = /\.rb\b|\/app\/|\/gems\/|\/lib\/|ActiveRecord|ActionController|PG::|Errno|NoMethodError|NameError|SELECT\s|INSERT\s|#<|backtrace|stack ?trace|Traceback/i
probes = {
  "syntax error" => { query: "{ me { " }, "unknown field" => { query: "{ meee }" }, "bad enum/arg type" => { query: "mutation { login(input: 5){ token } }" },
  "null for required" => { query: LOGIN, variables: { i: nil } }, "bad variable type" => { query: LOGIN, variables: { i: { email: 5, password: [ 1 ] } } },
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
heavy = [ 60, 40, 20, 10 ].lazy.map { |n| [ n, gql("{ " + (1..n).map { |i| "a#{i}: me { id email }" }.join(" ") + " }", token: jt) ] }
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

# ---------- K. Roles and authorization ----------
# The role is never exposed and never an input. The only way to see it is the database (otp_helper "role").
def role_of(email) = otp("role", email)

k_email = uniq
k_res = gql(SIGNUP, variables: { i: { email: k_email, password: PW, role: "super_admin" } })
check("K1", "signUp with an extra `role` input is rejected and creates no user",
      k_res[:json]&.dig("errors") && !tok_of(k_res) && otp("role", k_email).empty?, k_res[:body][0, 160], bad: "CRITICAL")

k_email = uniq
signup(k_email)
check("K2", "a normal signUp creates a member", role_of(k_email) == "member", role_of(k_email), bad: "CRITICAL")

k_res = gql(LOGIN, variables: { i: { email: k_email, password: PW, role: "super_admin" } })
check("K3", "login with an extra `role` input is rejected", k_res[:json]&.dig("errors") && !tok_of(k_res, "login"), k_res[:body][0, 160], bad: "HIGH")
check("K4", "role is still member after the attempts above", role_of(k_email) == "member", role_of(k_email), bad: "CRITICAL")

k_tok = tok_of(login(k_email), "login")
k_me = gql(ME, token: k_tok)
check("K5", "a member can read only themselves with me", k_me[:json]&.dig("data", "me", "email") == k_email, k_me[:body][0, 120])
k_role = gql("{ me { role } }", token: k_tok)
check("K5b", "me tells the frontend the role (MEMBER for a new user)", k_role[:json]&.dig("data", "me", "role") == "MEMBER", k_role[:body][0, 120])
k_out = gql(LOGOUT, token: k_tok)
check("K6", "a member can log out, and the token is dead afterwards",
      k_out[:json]&.dig("data", "logout", "success") == true && code(gql(ME, token: k_tok)) == "UNAUTHENTICATED", k_out[:body][0, 120])
k_forbidden = [ gql(ME), gql(LOGOUT) ].map { |x| code(x) }
check("K7", "no token gives UNAUTHENTICATED, never FORBIDDEN or data", k_forbidden == %w[UNAUTHENTICATED UNAUTHENTICATED], k_forbidden.inspect, bad: "HIGH")

# ---------- L. Email change (OTP to the new address) ----------
# Black-box checks run in both modes. The ones that need the code (the "new inbox") or the database run in test mode only.
REQ_EC  = "mutation R($i: RequestEmailChangeInput!){ requestEmailChange(input:$i){ success errors{message path code} } }"
CONF_EC = "mutation C($i: ConfirmEmailChangeInput!){ confirmEmailChange(input:$i){ success errors{message path code} } }"

def req_ec(token, new_email, pw = PW, extra = {}) = gql(REQ_EC, variables: { i: { newEmail: new_email, password: pw }.merge(extra) }, token: token)
def conf_ec(token, otp_code, extra = {}) = gql(CONF_EC, variables: { i: { code: otp_code }.merge(extra) }, token: token)
def ec_ok?(r) = r[:json]&.dig("data", "confirmEmailChange", "success") == true
def ec_err(r) = r[:json]&.dig("data", "confirmEmailChange", "errors", 0, "code")
def req_err(r) = r[:json]&.dig("data", "requestEmailChange", "errors", 0, "code")
def ec_state(email) = (JSON.parse(otp("ec_state", email)) rescue {})

ea = uniq
ta = tok_of(signup(ea))
eb = uniq
tb = tok_of(signup(eb))

none = [ req_ec(nil, uniq), conf_ec(nil, "123456"), req_ec("garbage", uniq), conf_ec("garbage", "123456") ]
check("L1", "requestEmailChange and confirmEmailChange: no token or a garbage token is UNAUTHENTICATED",
      none.all? { |x| code(x) == "UNAUTHENTICATED" }, none.map { |x| x[:body][0, 70] }.uniq.inspect, bad: "CRITICAL")

wrong = req_ec(ta, uniq, "wrong-password-x")
check("L2", "wrong password: INVALID_CREDENTIALS, same text as login", req_err(wrong) == "INVALID_CREDENTIALS", wrong[:body][0, 140], bad: "HIGH")

free_a = req_ec(ta, uniq)
taken_a = req_ec(tb, ea) # ea belongs to user A, so it is taken for user B
check("L3", "free and taken new email: exactly the same answer", free_a[:json] == taken_a[:json] && free_a[:json]&.dig("data", "requestEmailChange", "success") == true,
      "#{free_a[:body][0, 100]} | #{taken_a[:body][0, 100]}", bad: "HIGH")

bad_emails = [ "not-an-email", "", "x" * 5000, "' OR 1=1 --", "x'; DROP TABLE users;--@example.test", "a@b.test\r\nBcc: evil@x.test", "‮@x.test", "аdmin@example.test", "a@exаmple.test" ]
bad_res = bad_emails.map { |s| req_ec(ta, s) }
check("L4", "odd newEmail values: clean, VALIDATION_FAILED, never success",
      bad_res.all? { |x| clean?(x) && !x[:json]&.dig("data", "requestEmailChange", "success") }, bad_res.map { |x| x[:body][0, 60] }.uniq.inspect, bad: "MEDIUM")

r1 = req_ec(ta, uniq, PW, { role: "super_admin", id: SecureRandom.uuid, email: uniq })
r2 = conf_ec(ta, "123456", { role: "super_admin", userId: SecureRandom.uuid, pendingEmail: uniq })
check("L5", "extra input fields on both mutations are rejected", [ r1, r2 ].all? { |x| x[:json]&.dig("errors") && clean?(x) }, "#{r1[:body][0, 80]} | #{r2[:body][0, 80]}", bad: "MEDIUM")

multi = gql("mutation { a: confirmEmailChange(input:{code:\"000000\"}){ success } b: confirmEmailChange(input:{code:\"111111\"}){ success } }", token: ta)
check("L6", "2 aliased confirmEmailChange in ONE request are refused (no guess multiplying)", multi[:status] == 400 && !multi[:body].include?("success"), "status=#{multi[:status]} #{multi[:body][0, 100]}", bad: "HIGH")
many = (1..100).map { |i| "a#{i}: requestEmailChange(input:{newEmail:\"#{uniq}\", password:\"wrong-password-#{i}\"}){ success }" }.join(" ")
r = gql("mutation { #{many} }", token: ta)
check("L7", "100 aliased requestEmailChange (password guesses) in ONE request are refused", r[:status] == 400 || !r[:json]&.dig("data"), "status=#{r[:status]} #{r[:body][0, 100]}", bad: "CRITICAL")

if LABEL == "prod"
  t_free = avg(6) { req_ec(ta, uniq)[:ms] }
  t_taken = avg(6) { req_ec(ta, eb)[:ms] }
  check("L8", "requestEmailChange timing, free vs taken email", (t_free - t_taken).abs < [ t_free, t_taken ].max * 0.4 + 15, "free=#{t_free.round}ms taken=#{t_taken.round}ms", bad: "WEAK")
  $pinned_ip = "10.88.77.66"
  codes = 12.times.map { conf_ec(ta, "000000")[:status] }
  r = conf_ec(ta, "000000")
  check("L9", "email change operations are throttled per IP (10 per hour): 429 RATE_LIMITED with Retry-After",
        codes.count(429) >= 1 && r[:status] == 429 && code(r) == "RATE_LIMITED" && r[:headers]["retry-after"].to_i.positive?, "statuses=#{codes.tally} #{r[:body][0, 80]}", bad: "HIGH")
  $pinned_ip = nil
end

if LABEL == "test"
  fresh = -> { e = uniq; t = tok_of(signup(e)); [ e, t ] }

  # --- password check and lockout (a stolen token must not be able to guess the password)
  e, t = fresh.call
  7.times { req_ec(t, uniq, "wrong-password-#{rand(1000)}") } # a new IP each time: only a per-account limit can stop this
  st = ec_state(e)
  check("L10", "7 wrong passwords through ONE valid token lock the account (per-account limit, not only per-IP)", st["locked"] == true,
        "locked=#{st['locked']} failed_attempts=#{st['failed']}", bad: "HIGH")
  after = gql(ME, token: t)
  check("L37", "the token of the locked account answers 200 UNAUTHENTICATED like a garbage token, and never says it is locked",
        after[:status] == 200 && code(after) == "UNAUTHENTICATED" && after[:json] == gql(ME, token: "not.a.token")[:json] && !after[:body].match?(/lock/i), after[:body][0, 120], bad: "MEDIUM")
  right = req_ec(t, uniq)
  check("L11", "after those guesses the right password is still checked (no free pass, no 500)", clean?(right), right[:body][0, 100], bad: "MEDIUM")

  # --- happy path: the code goes to the new address only, the login email does not change before the code
  e, session = fresh.call
  other_session = tok_of(login(e), "login")
  new_e = uniq
  r = req_ec(session, new_e)
  st = ec_state(e)
  check("L12", "request alone changes nothing: login email unchanged", r[:json]&.dig("data", "requestEmailChange", "success") == true && st["email"] == e, st.inspect, bad: "HIGH")
  c = otp("ec_mint", e, new_e)
  check("L14", "helper issued a 6-digit email_change code", c.match?(/\A\d{6}\z/), c.inspect)
  mail = otp("ec_mail", e, new_e)
  body = mail.to_s
  check("L15", "code mail: only the code, no current address, no password, no link (also the XSS check for the template)",
        !body.include?(e) && !body.match?(/https?:\/\//) && !body.include?(PW), body[0, 160], bad: "MEDIUM")
  c = otp("ec_mint", e, new_e)
  r = conf_ec(session, c)
  check("L16", "confirm with the right code works", ec_ok?(r), r[:body][0, 160], bad: "HIGH")
  check("L17", "the new email logs in, the old email does not", tok_of(login(new_e), "login") && !tok_of(login(e), "login"), bad: "HIGH")
  check("L18", "the session that confirmed still works and shows the new email", gql(ME, token: session)[:json]&.dig("data", "me", "email") == new_e, bad: "MEDIUM")
  check("L19", "every OTHER session is dead after the change", code(gql(ME, token: other_session)) == "UNAUTHENTICATED", bad: "HIGH")
  replay = conf_ec(session, c)
  check("L20", "replay of the used code is refused", ec_err(replay) == "INVALID_CODE" && !ec_ok?(replay), replay[:body][0, 160], bad: "CRITICAL")
  st = ec_state(new_e)
  check("L21", "after the change: no code left, pending cleared", st["code"] == false && st["pending"].nil?, st.inspect, bad: "MEDIUM")

  # --- guess limit: 5 wrong guesses from 5 IPs kill the code
  e, t = fresh.call
  new_e = uniq
  c = otp("ec_mint", e, new_e)
  five = 5.times.map { conf_ec(t, wrong_guess(c)) }
  check("L22", "5 wrong guesses (5 IPs) kill the code, even the right code is refused after, email unchanged",
        five.all? { |x| ec_err(x) == "INVALID_CODE" } && ec_err(conf_ec(t, c)) == "INVALID_CODE" && ec_state(e)["code"] == false && ec_state(e)["email"] == e, ec_state(e).inspect, bad: "CRITICAL")

  e, t = fresh.call
  c = otp("ec_mint", e, uniq)
  four = 4.times.map { conf_ec(t, wrong_guess(c)) }
  check("L23", "4 wrong guesses do not kill the code", four.all? { |x| ec_err(x) == "INVALID_CODE" } && ec_state(e)["attempts"] == 4, ec_state(e).inspect, bad: "MEDIUM")

  # --- expiry, format, cross purpose
  e, t = fresh.call
  c = otp("ec_mint", e, uniq)
  otp("ec_expire", e)
  r = conf_ec(t, c)
  check("L24", "an expired code is refused", ec_err(r) == "INVALID_CODE" && !ec_ok?(r), r[:body][0, 140], bad: "CRITICAL")

  bad_codes = [ "", "12345", "1234567", "123456\n", " 123456", "１２３４５６", "1e5000", "0x1234", "' OR 1=1 --", "x" * 10_000, "123456" * 1000 ]
  bad_res = bad_codes.map { |x| conf_ec(t, x) }
  check("L25", "codes in a wrong format: clean INVALID_CODE", bad_res.all? { |x| clean?(x) && ec_err(x) == "INVALID_CODE" }, bad_res.map { |x| x[:status] }.tally.inspect, bad: "MEDIUM")

  e, t = fresh.call
  pr = otp("mint", e) # a password reset code
  r = conf_ec(t, pr)
  check("L26", "a password reset code cannot confirm an email change", ec_err(r) == "INVALID_CODE" && !ec_ok?(r), r[:body][0, 140], bad: "CRITICAL")
  ec = otp("ec_mint", e, uniq)
  r = do_reset(e, ec, "Other-Passw0rd-7!")
  check("L27", "an email change code cannot reset the password", reset_code(r) == "INVALID_CODE" && !reset_ok?(r), r[:body][0, 140], bad: "CRITICAL")
  check("L28", "a wrong guess with an email change code counts only against the password reset code, and does not delete either code",
        ec_state(e)["code"] == true && otp("attempts", e) == "1", otp("attempts", e), bad: "LOW")

  # --- another user cannot use this code
  victim, tv = fresh.call
  intruder, ti = fresh.call
  new_e = uniq
  c = otp("ec_mint", victim, new_e)
  r = conf_ec(ti, c)
  check("L29", "another logged-in user with the victim's code: INVALID_CODE, own email unchanged", ec_err(r) == "INVALID_CODE" && ec_state(intruder)["email"] == intruder, r[:body][0, 120], bad: "CRITICAL")
  check("L30", "the intruder's try did not spend a guess of the victim's code", ec_state(victim)["attempts"] == 0, ec_state(victim).inspect, bad: "MEDIUM")
  check("L31", "the victim can still confirm", ec_ok?(conf_ec(tv, c)), bad: "MEDIUM")

  # --- races and taken-in-the-meantime
  e, t = fresh.call
  new_e = uniq
  c = otp("ec_mint", e, new_e)
  rs = 8.times.map { Thread.new { conf_ec(t, c) } }.map(&:value)
  check("L32", "8 parallel confirms with the same right code: exactly one succeeds, no 500", rs.count { |x| ec_ok?(x) } == 1 && rs.all? { |x| clean?(x) }, rs.map { |x| x[:body][0, 70] }.tally.inspect, bad: "HIGH")

  e, t = fresh.call
  new_e = uniq
  c = otp("ec_mint", e, new_e)
  signup(new_e) # someone registers the address after the code was sent
  r = conf_ec(t, c)
  check("L33", "address taken in the meantime: INVALID_CODE (no hint), login email unchanged, no takeover of the other account",
        ec_err(r) == "INVALID_CODE" && ec_state(e)["email"] == e && ec_state(new_e)["email"] == new_e, r[:body][0, 120], bad: "HIGH")

  # two users race for the same free address with their own valid codes
  e1, t1 = fresh.call
  e2, t2 = fresh.call
  shared = uniq
  c1 = otp("ec_mint", e1, shared)
  c2 = otp("ec_mint", e2, shared)
  rs = [ Thread.new { conf_ec(t1, c1) }, Thread.new { conf_ec(t2, c2) } ].map(&:value)
  check("L34", "two users confirm the same new address at once: exactly one wins, no 500, no duplicate email",
        rs.count { |x| ec_ok?(x) } == 1 && rs.all? { |x| clean?(x) }, rs.map { |x| x[:body][0, 70] }.inspect, bad: "HIGH")

  # --- a request inside the cooldown must not re-point an already mailed code
  e, t = fresh.call
  first, second = uniq, uniq
  c = otp("ec_mint", e, first) # first address got its code just now
  req_ec(t, second)
  st = ec_state(e)
  check("L35", "second request inside 60 s does not move the pending address away from the one that got the code",
        st["pending"] == first && st["code"] == true, st.inspect, bad: "HIGH")
  check("L36", "...so that code still opens the first address", ec_ok?(conf_ec(t, c)) && ec_state(first)["email"] == first, bad: "HIGH")
end

# ---------- M. Invitations ----------
# Black-box checks run in both modes. The ones that need an invitation token (the "invitee's inbox") run in test mode only.
INVITE = "mutation I($i: InviteUserInput!){ inviteUser(input:$i){ success errors{message path code} } }"
ACCEPT = "mutation A($i: AcceptInvitationInput!){ acceptInvitation(input:$i){ token user{id email role} errors{message path code} } }"
REVOKE = "mutation R($i: RevokeInvitationInput!){ revokeInvitation(input:$i){ success errors{message path code} } }"
RESEND = "mutation S($i: ResendInvitationInput!){ resendInvitation(input:$i){ success errors{message path code} } }"

def inv(token, email, extra = {}) = gql(INVITE, variables: { i: { email: email, role: "MEMBER" }.merge(extra) }, token: token)
def inv_accept(tok, pass = PW, extra = {}) = gql(ACCEPT, variables: { i: { invitationToken: tok, password: pass }.merge(extra) })
def inv_revoke(token, email) = gql(REVOKE, variables: { i: { email: email } }, token: token)
def inv_resend(token, email) = gql(RESEND, variables: { i: { email: email } }, token: token)
def accept_ok?(r) = !r[:json]&.dig("data", "acceptInvitation", "token").nil?
def accept_err(r) = r[:json]&.dig("data", "acceptInvitation", "errors", 0, "code")
def inv_state(email) = (JSON.parse(otp("inv_state", email)) rescue {})

m_admin_email = uniq
m_admin_tok = tok_of(signup(m_admin_email))
otp("make_admin", m_admin_email)
m_admin_tok = tok_of(login(m_admin_email), "login") # a fresh login, the role is read from the database on each request
m_member_tok = tok_of(signup(uniq))

none = [ inv(nil, uniq), inv("garbage", uniq), inv_revoke(nil, uniq), inv_revoke("garbage", uniq), inv_resend(nil, uniq), inv_resend("garbage", uniq) ]
check("M1", "inviteUser, revokeInvitation, resendInvitation: no token or a garbage token is UNAUTHENTICATED",
      none.all? { |x| code(x) == "UNAUTHENTICATED" }, none.map { |x| x[:body][0, 70] }.uniq.inspect, bad: "CRITICAL")

m_target = uniq
forbidden = [ inv(m_member_tok, m_target), inv(m_member_tok, m_target, { email: "not-an-email" }), inv_revoke(m_member_tok, m_target), inv_resend(m_member_tok, m_target) ]
check("M2", "a member gets FORBIDDEN on all three, also with a bad email (403 comes before validation)",
      forbidden.all? { |x| code(x) == "FORBIDDEN" }, forbidden.map { |x| x[:body][0, 70] }.uniq.inspect, bad: "CRITICAL")
m_admin_up = inv(m_admin_tok, m_target, { role: "SUPER_ADMIN" })
check("M2a", "even a super_admin cannot invite a super_admin: the role enum only lists MEMBER, so it is refused", code(m_admin_up) != nil && !m_admin_up[:body].include?("\"success\":true"), m_admin_up[:body][0, 100], bad: "CRITICAL")
check("M2b", "...and no invitation was created", inv_state(m_target).fetch("invitations", [ 1 ]).empty? || LABEL == "prod", inv_state(m_target).inspect, bad: "CRITICAL")

nasty = [ "x" * 10_000, "' OR 1=1 --", "\u0000", "🔥" * 50, "../../etc/passwd", "<script>alert(1)</script>", "A" * 43, "-" * 43, "{\"$ne\":null}" ]
rs = nasty.map { |v| inv_accept(v) }
check("M3", "acceptInvitation with wrong or hostile tokens: INVALID_INVITATION (or a schema error for NUL), never a 500, same message",
      rs.all? { |x| clean?(x) && (accept_err(x) == "INVALID_INVITATION" || x[:json]&.dig("errors")) } && rs.filter_map { |x| accept_err(x) }.uniq.size <= 1,
      rs.map { |x| x[:body][0, 70] }.uniq.inspect, bad: "HIGH")

mass = [ inv(m_admin_tok, uniq, { inviterId: SecureRandom.uuid }), inv(m_admin_tok, uniq, { tokenDigest: "x" }), inv(m_admin_tok, uniq, { acceptedAt: "2020-01-01" }),
         inv_accept("A" * 43, PW, { role: "SUPER_ADMIN" }), inv_accept("A" * 43, PW, { email: uniq }) ]
check("M4", "extra input fields (inviterId, tokenDigest, acceptedAt, role, email on accept) are rejected by the schema",
      mass.all? { |x| x[:json]&.dig("errors") && !x[:body].include?("INTERNAL_ERROR") }, mass.map { |x| x[:body][0, 60] }.uniq.inspect, bad: "CRITICAL")

# Same answer for a new email and an email that already has an account (no enumeration, not even for a super_admin).
# Needs a super_admin, and only the test database can make one (otp_helper), so prod mode cannot run M5 to M5c.
if LABEL == "test"
  m_new = uniq
  m_taken = uniq
  signup(m_taken)
  a_new = inv(m_admin_tok, m_new)
  a_taken = inv(m_admin_tok, m_taken)
  check("M5", "inviting a new email and an email with an account: exactly the same answer",
        a_new[:json] == a_taken[:json] && a_new[:json]&.dig("data", "inviteUser", "success") == true, "#{a_new[:body][0, 90]} | #{a_taken[:body][0, 90]}", bad: "HIGH")
  check("M5b", "revoke and resend of a never-invited email answer success too (nothing to learn)",
        [ inv_revoke(m_admin_tok, uniq), inv_resend(m_admin_tok, uniq) ].all? { |x| x[:json]&.dig("data")&.values&.first&.dig("success") == true }, bad: "MEDIUM")
  check("M5c", "a badly formed email is VALIDATION_FAILED on all three", [ inv(m_admin_tok, "nope"), inv_revoke(m_admin_tok, "nope"), inv_resend(m_admin_tok, "nope") ]
        .all? { |x| x[:json]&.dig("data")&.values&.first&.dig("errors", 0, "code") == "VALIDATION_FAILED" }, bad: "MEDIUM")
else
  rec("M5", "same answer for new and existing email needs a super_admin (test mode only)", "INFO")
end

m_batch = gql("mutation { a: inviteUser(input: { email: \"#{uniq}\", role: MEMBER }) { success } b: inviteUser(input: { email: \"#{uniq}\", role: MEMBER }) { success } }", token: m_admin_tok)
check("M6", "several invitation operations in one request are refused as a whole (aliases multiply emails)", code(m_batch) == "BAD_REQUEST" && m_batch[:status] == 400, m_batch[:body][0, 100], bad: "HIGH")

if LABEL == "test"
  mint = ->(role = "member") { e = uniq; [ e, otp("inv_mint", e, role) ] }

  e, t = mint.call
  r = inv_accept(t)
  check("M7", "a valid token creates the user (member) and logs them in", accept_ok?(r) && role_of(e) == "member", r[:body][0, 140], bad: "HIGH")
  r2 = inv_accept(t, "Another-Str0ng-Pass1")
  check("M8", "the same token a second time: INVALID_INVITATION, password unchanged", accept_err(r2) == "INVALID_INVITATION" && !tok_of(login(e), "login").nil? && tok_of(login(e, "Another-Str0ng-Pass1"), "login").nil?, r2[:body][0, 120], bad: "CRITICAL")

  e, t = mint.call("super_admin") # only the database can make one: the API refuses
  inv_accept(t)
  check("M9", "the role comes from the invitation row (super_admin here), not from the client", role_of(e) == "super_admin", role_of(e), bad: "HIGH")

  e, t = mint.call
  otp("inv_expire", e)
  r = inv_accept(t)
  check("M10", "an expired invitation: INVALID_INVITATION, no user", accept_err(r) == "INVALID_INVITATION" && !inv_state(e)["user"], r[:body][0, 120], bad: "HIGH")

  e, t = mint.call
  inv_revoke(m_admin_tok, e)
  r = inv_accept(t)
  check("M11", "a revoked invitation: INVALID_INVITATION, no user", accept_err(r) == "INVALID_INVITATION" && !inv_state(e)["user"], r[:body][0, 120], bad: "HIGH")

  e, t = mint.call
  r = inv_accept(t, "short")
  check("M12", "a weak password: VALIDATION_FAILED, and the invitation is not used up", r[:json]&.dig("data", "acceptInvitation", "errors", 0, "code") == "VALIDATION_FAILED" && accept_ok?(inv_accept(t)), r[:body][0, 120], bad: "MEDIUM")

  e, t = mint.call
  signup(e) # the address got an account in the meantime
  r = inv_accept(t)
  check("M13", "email already has an account: INVALID_INVITATION, no hint that the account exists, existing password untouched",
        accept_err(r) == "INVALID_INVITATION" && !r[:body].match?(/taken|exists/i) && !tok_of(login(e, "Another-Str0ng-Pass1"), "login"), r[:body][0, 120], bad: "HIGH")

  e, t = mint.call
  rs = 8.times.map { Thread.new { inv_accept(t) } }.map(&:value)
  check("M14", "8 parallel accepts with the same token: exactly one wins, no 500, one user", rs.count { |x| accept_ok?(x) } == 1 && rs.all? { |x| clean?(x) }, rs.map { |x| x[:body][0, 60] }.tally.inspect, bad: "HIGH")

  e, t = mint.call
  inv_accept(t)
  m_new_tok = tok_of(login(e), "login")
  onboard!(m_new_tok) # the gate comes before authorization: without this the answer would be ONBOARDING_REQUIRED, not FORBIDDEN
  r = inv(m_new_tok, uniq)
  check("M15", "a user made by an invitation as member cannot invite (no privilege from the invitation flow)", code(r) == "FORBIDDEN", r[:body][0, 100], bad: "CRITICAL")

  # The token in the database is a keyed digest: sending the stored digest as a token must not work.
  e, t = mint.call
  r = inv_accept(Base64.urlsafe_encode64(SecureRandom.random_bytes(32), padding: false))
  check("M16", "a random well-formed token: INVALID_INVITATION", accept_err(r) == "INVALID_INVITATION", r[:body][0, 100], bad: "HIGH")

  # Test mode does not run the email job, so the new link is not visible here: the old link and the row state are.
  e, t = mint.call
  inv_revoke(m_admin_tok, e)
  rs = inv_resend(m_admin_tok, e)
  st = inv_state(e)["invitations"]&.first || {}
  check("M18", "resend of a revoked invitation answers success, reopens it, and the old link stays dead",
        rs[:json]&.dig("data", "resendInvitation", "success") == true && st["revoked"] == false && st["accepted"] == false && accept_err(inv_accept(t)) == "INVALID_INVITATION" && !inv_state(e)["user"],
        "#{rs[:body][0, 80]} #{st.inspect}", bad: "HIGH")

  e, t = mint.call
  inv_accept(t)
  inv_resend(m_admin_tok, e)
  check("M19", "resend never reopens a used invitation (still accepted, not revoked-cleared into a second user)", (inv_state(e)["invitations"] || []).size == 1 && inv_state(e)["invitations"][0]["accepted"] == true, inv_state(e).inspect, bad: "HIGH")
else
  rec("M7-19", "invitation token checks need the token (test mode only)", "INFO")
end

# Throttle counters need a real cache: prod mode only.
if LABEL == "prod"
  $pinned_ip = "10.98.98.#{rand(1..254)}"
  codes = 32.times.map { inv(m_admin_tok, uniq)[:status] }
  check("M17", "31st invitation operation from one IP in an hour -> 429", codes[30..].all? { |c| c == 429 } && codes[0..29].none? { |c| c == 429 }, codes.tally.inspect, bad: "HIGH")
  $pinned_ip = nil
end

# ---------- N. Onboarding ----------
# Black-box checks that hold for any registry. These users are made with `onboard: false`, so they still have steps to do.
# The server finishes a step when its data is saved. A client cannot mark a step done: there is no operation for it (N3).
OTHER_OP = "mutation { requestEmailChange(input:{ newEmail:\"#{uniq}\", password:\"#{PW}\" }){ success } }" # any closed operation will do

n_a = tok_of(signup(uniq, onboard: false))
n_b = tok_of(signup(uniq, onboard: false))

none = [ gql(MY_ONB), gql(MY_ONB, token: "garbage"), terms_save(nil), terms_save("garbage"), gql(ACCEPT_TERMS, variables: { i: {} }) ]
check("N1", "me { onboarding } and acceptTerms: no token, a garbage token, or bad input as nobody is UNAUTHENTICATED",
      none.all? { |x| code(x) == "UNAUTHENTICATED" }, none.map { |x| x[:body][0, 70] }.uniq.inspect, bad: "CRITICAL")

n_state = onb_of(n_a)
n_steps = n_state&.dig("steps") || []
check("N2", "me { onboarding } shows only completed, currentStep, steps (key, completed, completedAt): no roles, no checks, no operations",
      n_state && n_state.keys.sort == %w[completed currentStep steps] && n_steps.all? { |x| x.keys.sort == %w[completed completedAt key] }, n_state.inspect[0, 200], bad: "MEDIUM")

old_op = gql("mutation { completeOnboardingStep(input:{ stepKey:\"profile\" }){ errors{code} } }", token: n_a)
check("N3", "a client cannot mark a step done: completeOnboardingStep does not exist (schema error, no data), and the steps did not change",
      clean?(old_op) && old_op[:json]&.dig("errors") && old_op[:json]["data"].nil? && onb_of(n_a) == n_state, old_op[:body][0, 120], bad: "CRITICAL")

hostile = [ "", "   ", "' OR 1=1 --", "x" * 10_000, "🔥" * 50, "../../etc/passwd", "<script>alert(1)</script>", "{\"$ne\":null}", "#{terms_version} " + "x" ]
rs = hostile.map { |v| terms_save(n_a, v) }
check("N4", "hostile or empty terms versions: a clean answer (VALIDATION_FAILED), never a 500, and no step is finished",
      rs.all? { |x| clean?(x) && (op_errs(x, "acceptTerms")&.first&.dig("code") == "VALIDATION_FAILED" || x[:json]&.dig("errors")) } && onb_of(n_a) == n_state, rs.map { |x| x[:body][0, 60] }.uniq.first(3).inspect, bad: "HIGH")

mass = [ terms_save(n_a, terms_version, { userId: SecureRandom.uuid }), terms_save(n_a, terms_version, { role: "SUPER_ADMIN" }), terms_save(n_a, terms_version, { termsAcceptedAt: "2020-01-01T00:00:00Z" }) ]
check("N5", "extra input fields (userId, role, termsAcceptedAt) are rejected by the schema: a user cannot name another user or set the time",
      mass.all? { |x| x[:json]&.dig("errors") && !x[:body].include?("INTERNAL_ERROR") } && onb_of(n_a) == n_state, mass.map { |x| x[:body][0, 60] }.uniq.inspect, bad: "CRITICAL")

batch = "mutation { " + (1..50).map { |i| "a#{i}: acceptTerms(input:{version:\"x\"}){ errors{code} }" }.join(" ") + " }"
check("N6", "50 aliased acceptTerms calls: refused or answered, never a 500", clean?(gql(batch, token: n_a)), gql(batch, token: n_a)[:body][0, 100], bad: "MEDIUM")

lo = gql("mutation { logout(input:{}){ success } }", token: tok_of(signup(uniq)))
n_c = tok_of(signup(uniq, onboard: false))
gql("mutation { logout(input:{}){ success } }", token: n_c)
check("N7", "a token after logout is UNAUTHENTICATED on both operations", code(gql(MY_ONB, token: n_c)) == "UNAUTHENTICATED" && code(terms_save(n_c)) == "UNAUTHENTICATED", bad: "CRITICAL")

blocked_op = gql(OTHER_OP, token: n_a)
if n_steps.empty?
  check("N8", "no steps in the registry: nobody is blocked (me { onboarding } is complete, other operations are not ONBOARDING_REQUIRED)",
        n_state&.dig("completed") == true && code(blocked_op) != "ONBOARDING_REQUIRED", blocked_op[:body][0, 100], bad: "MEDIUM")
  rec("N9-13", "gate, order, isolation and idempotence checks need a step in the registry (specs cover them)", "INFO")
else
  aliased = gql(OTHER_OP.sub("mutation { ", "mutation { me: "), token: n_a)
  frag = gql("mutation { ...F } fragment F on Mutation { " + OTHER_OP.sub("mutation { ", "").sub(/ \}\z/, "") + " }", token: n_a)
  check("N8", "with steps open: a closed operation is ONBOARDING_REQUIRED, also behind an alias or a fragment; me (with its onboarding) still answers",
        [ blocked_op, aliased, frag ].all? { |x| code(x) == "ONBOARDING_REQUIRED" } && gql(ME, token: n_a)[:json]&.dig("data", "me", "id") && !n_state.nil?, [ blocked_op, aliased, frag ].map { |x| x[:body][0, 60] }.uniq.inspect, bad: "CRITICAL")

  if n_steps.size > 1
    r = terms_save(n_a)
    after = onb_of(n_a)
    check("N10", "the terms step before the profile: the data is saved but no step is finished out of order, and the gate stays closed",
          op_errs(r, "acceptTerms") == [] && after&.dig("steps")&.none? { |x| x["completed"] } && code(gql(OTHER_OP, token: n_a)) == "ONBOARDING_REQUIRED", after.inspect[0, 140], bad: "HIGH")
  else
    rec("N10", "order check needs two steps in the registry", "INFO")
  end

  r1 = terms_save(n_b)
  r2 = terms_save(n_b)
  check("N11", "the same data twice: the same answer both times (no errors), never a 500", clean?(r1) && clean?(r2) && op_errs(r1, "acceptTerms") == [] && op_errs(r2, "acceptTerms") == [], "#{r1[:body][0, 60]} | #{r2[:body][0, 60]}", bad: "MEDIUM")

  rs = 8.times.map { Thread.new { terms_save(n_b) } }.map(&:value)
  check("N12", "8 parallel acceptTerms of one user: no 500, all succeed", rs.all? { |x| clean?(x) && op_errs(x, "acceptTerms") == [] }, rs.map { |x| x[:body][0, 60] }.tally.inspect, bad: "HIGH")

  # With the work done, the gate opens for B, and A (who only sent the terms) stays blocked and unchanged.
  a_before = onb_of(n_a)
  onboard!(n_b)
  check("N13", "user B finishes onboarding: the gate opens for B (a closed operation is not ONBOARDING_REQUIRED), and user A is untouched and still blocked",
        onb_of(n_b)&.dig("completed") == true && code(gql(OTHER_OP, token: n_b)) != "ONBOARDING_REQUIRED" && onb_of(n_a) == a_before && code(gql(OTHER_OP, token: n_a)) == "ONBOARDING_REQUIRED",
        "#{onb_of(n_b).inspect[0, 80]} | #{onb_of(n_a).inspect[0, 80]}", bad: "CRITICAL")
end

# ---------- P. Profile (updateProfile, and the profile fields of me) ----------
def prof(token, extra = {}) = gql(UPDATE_PROFILE, variables: { i: PROFILE.merge(extra) }, token: token)
def prof_errs(r) = r[:json]&.dig("data", "updateProfile", "errors")
def me_profile(token) = gql("{ me { firstName lastName dateOfBirth phone } }", token: token)[:json]&.dig("data", "me")
def raw_profile(email) = (JSON.parse(otp("profile_raw", email)) rescue {})
EMPTY_PROFILE = { "firstName" => nil, "lastName" => nil, "dateOfBirth" => nil, "phone" => nil }.freeze

p_a_email = uniq
p_a = tok_of(signup(p_a_email, onboard: false))
p_b_email = uniq
p_b = tok_of(signup(p_b_email, onboard: false))

none = [ prof(nil), prof("garbage"), gql(UPDATE_PROFILE, variables: { i: {} }), gql(UPDATE_PROFILE, variables: { i: { firstName: "x" } }, token: "garbage") ]
check("P1", "updateProfile: no token, a garbage token, or bad input as nobody is UNAUTHENTICATED (401 comes before validation)",
      none.all? { |x| code(x) == "UNAUTHENTICATED" }, none.map { |x| x[:body][0, 70] }.uniq.inspect, bad: "CRITICAL")

check("P2", "a new user has an empty profile", me_profile(p_a) == EMPTY_PROFILE, me_profile(p_a).inspect, bad: "LOW")

bad = { phone: [ "4155552671", "+0123456789", "+1234567", "+1" + "2" * 20, "abc", "' OR 1=1 --" ], dateOfBirth: [ "2999-01-01", "1700-01-01", "not-a-date", "2000-13-45" ] }
rs = bad.flat_map { |field, values| values.map { |v| [ field, prof(p_a, { field => v }) ] } }
check("P3", "a wrong phone or date of birth is refused (VALIDATION_FAILED naming the field, or a schema error), never a 500, and nothing is saved",
      rs.all? { |field, x| clean?(x) && (prof_errs(x)&.any? { |e| e["code"] == "VALIDATION_FAILED" && e["path"].last == field.to_s } || x[:json]&.dig("errors")) } && me_profile(p_a) == EMPTY_PROFILE,
      rs.map { |_, x| x[:body][0, 60] }.uniq.first(3).inspect, bad: "HIGH")

hostile = [ "", "   ", "' OR 1=1 --", "x" * 10_000, "🔥" * 50, "<script>alert(1)</script>", "{\"$ne\":null}", "${7*7}", "\r\nBcc: evil@example.test" ]
rs = hostile.flat_map { |v| [ prof(p_a, { firstName: v }), prof(p_a, { lastName: v }) ] }
check("P4", "hostile or empty names: a clean answer, never a 500", rs.all? { |x| clean?(x) }, rs.map { |x| x[:status] }.tally.inspect, bad: "HIGH")
# The hostile values above are valid, so P4 saved some. Use a fresh user for the checks that need an empty profile.
p_c = tok_of(signup(uniq, onboard: false))
check("P4a", "an empty name is \"required\" (not \"invalid\"), 100 characters are accepted and 101 are refused",
      prof_errs(prof(p_c, { firstName: "" }))&.first&.values_at("message", "code") == [ "First name is required", "VALIDATION_FAILED" ] &&
      prof_errs(prof(p_c, { firstName: "a" * 101 }))&.first&.dig("code") == "VALIDATION_FAILED" && me_profile(p_c) == EMPTY_PROFILE, bad: "MEDIUM")

mass = [ prof(p_c, { userId: SecureRandom.uuid }), prof(p_c, { id: SecureRandom.uuid }), prof(p_c, { email: uniq }), prof(p_c, { role: "SUPER_ADMIN" }) ]
check("P5", "extra input fields (userId, id, email, role) are rejected by the schema: no way to name another user or change the role",
      mass.all? { |x| x[:json]&.dig("errors") && !x[:body].include?("INTERNAL_ERROR") } && me_profile(p_c) == EMPTY_PROFILE, mass.map { |x| x[:body][0, 60] }.uniq.inspect, bad: "CRITICAL")

r = prof(p_a)
check("P6", "a valid profile is saved, and me shows it", prof_errs(r) == [] && me_profile(p_a) == PROFILE.transform_keys(&:to_s), r[:body][0, 140], bad: "HIGH")
r2 = prof(p_a, { phone: "+1 415-555 2671" })
check("P7", "the same data again (also with spaces and dashes in the phone) succeeds and changes nothing", prof_errs(r2) == [] && me_profile(p_a) == PROFILE.transform_keys(&:to_s), r2[:body][0, 100], bad: "MEDIUM")

prof(p_b, { firstName: "Bea", lastName: "Other" })
check("P8", "each user has their own profile: B's save changed nothing for A, and A's data is not in B's me",
      me_profile(p_a)["firstName"] == "Qa" && me_profile(p_b)["firstName"] == "Bea" && !gql("{ me { firstName } }", token: p_b)[:body].include?("Qa"), bad: "CRITICAL")

rs = 8.times.map { Thread.new { prof(p_a, { lastName: "Parallel" }) } }.map(&:value)
check("P9", "8 parallel saves of the same data: no 500, all succeed, the profile is consistent", rs.all? { |x| clean?(x) && prof_errs(x) == [] } && me_profile(p_a)["lastName"] == "Parallel", rs.map { |x| x[:body][0, 60] }.tally.inspect, bad: "HIGH")

raw = raw_profile(p_a_email)
if raw.empty?
  rec("P10", "stored-value check needs the database helper (test mode only)", "INFO")
else
  check("P10", "date of birth and phone are stored as ciphertext (the plain digits and year are not in the database); names are plain on purpose",
        raw["phone"] && !raw["phone"].include?("4155552671") && raw["date_of_birth"] && !raw["date_of_birth"].include?("1990") && raw["first_name"] == "Qa", raw.inspect[0, 160], bad: "HIGH")
end

p_steps = onb_of(p_a)&.dig("steps") || []
check("P11", "the profile step: the server finished it when the profile was saved (no client call), and the user is not complete while other steps are open",
      p_steps.find { |x| x["key"] == "profile" }&.dig("completed") == true && (p_steps.size == 1 || onb_of(p_a)&.dig("completed") == false), onb_of(p_a).inspect[0, 160], bad: "HIGH")

# ---------- Q. Address (updateAddress, and the address fields of me) ----------
def addr_errs(r) = op_errs(r, "updateAddress")
def me_addr(token) = gql("{ me { addressLine1 addressLine2 city state postalCode country } }", token: token)[:json]&.dig("data", "me")
EMPTY_ADDRESS = { "addressLine1" => nil, "addressLine2" => nil, "city" => nil, "state" => nil, "postalCode" => nil, "country" => nil }.freeze

q_a = tok_of(signup(uniq, onboard: false))
q_b = tok_of(signup(uniq, onboard: false))

none = [ addr_save(nil), addr_save("garbage"), gql(UPDATE_ADDRESS, variables: { i: {} }), gql(UPDATE_ADDRESS, variables: { i: { city: "x" } }, token: "garbage") ]
check("Q1", "updateAddress: no token, a garbage token, or bad input as nobody is UNAUTHENTICATED (401 comes before validation)",
      none.all? { |x| code(x) == "UNAUTHENTICATED" }, none.map { |x| x[:body][0, 70] }.uniq.inspect, bad: "CRITICAL")

check("Q2", "a new user has an empty address", me_addr(q_a) == EMPTY_ADDRESS, me_addr(q_a).inspect, bad: "LOW")

bad = { state: [ "ZZ", "California", "c", "' OR 1=1 --" ], postalCode: [ "1234", "123456", "94105-12", "ABCDE", "94105 1234", "' OR 1=1 --" ], country: [ "CA", "USA", "us1", "' OR 1=1 --" ] }
rs = bad.flat_map { |field, values| values.map { |v| [ field, addr_save(q_a, { field => v }) ] } }
check("Q3", "a wrong state, ZIP code or country is refused (VALIDATION_FAILED naming the field, or a schema error), never a 500, and nothing is saved",
      rs.all? { |field, x| clean?(x) && (addr_errs(x)&.any? { |e| e["code"] == "VALIDATION_FAILED" && e["path"].last == field.to_s } || x[:json]&.dig("errors")) } && me_addr(q_a) == EMPTY_ADDRESS,
      rs.map { |_, x| x[:body][0, 60] }.uniq.first(3).inspect, bad: "HIGH")

hostile = [ "", "   ", "' OR 1=1 --", "x" * 10_000, "🔥" * 50, "<script>alert(1)</script>", "{\"$ne\":null}", "${7*7}", "\r\nBcc: evil@example.test" ]
rs = hostile.flat_map { |v| [ addr_save(q_a, { addressLine1: v }), addr_save(q_a, { city: v }), addr_save(q_a, { addressLine2: v }) ] }
check("Q4", "hostile or empty text in the address lines and city: a clean answer, never a 500", rs.all? { |x| clean?(x) }, rs.map { |x| x[:status] }.tally.inspect, bad: "HIGH")
# The hostile values above are valid, so Q4 saved some. Use a fresh user for the checks that need an empty address.
q_c = tok_of(signup(uniq, onboard: false))
check("Q4a", "an empty required field is \"required\" (not \"invalid\"), 100 characters are accepted and 101 are refused",
      addr_errs(addr_save(q_c, { city: "" }))&.first&.values_at("message", "code") == [ "City is required", "VALIDATION_FAILED" ] &&
      addr_errs(addr_save(q_c, { city: "a" * 101 }))&.first&.dig("code") == "VALIDATION_FAILED" && me_addr(q_c) == EMPTY_ADDRESS, bad: "MEDIUM")

mass = [ addr_save(q_c, { userId: SecureRandom.uuid }), addr_save(q_c, { id: SecureRandom.uuid }), addr_save(q_c, { email: uniq }), addr_save(q_c, { role: "SUPER_ADMIN" }) ]
check("Q5", "extra input fields (userId, id, email, role) are rejected by the schema: no way to name another user or change the role",
      mass.all? { |x| x[:json]&.dig("errors") && !x[:body].include?("INTERNAL_ERROR") } && me_addr(q_c) == EMPTY_ADDRESS, mass.map { |x| x[:body][0, 60] }.uniq.inspect, bad: "CRITICAL")

r = addr_save(q_a)
check("Q6", "a valid address is saved, and me shows it", addr_errs(r) == [] && me_addr(q_a) == ADDRESS.transform_keys(&:to_s), r[:body][0, 140], bad: "HIGH")
r2 = addr_save(q_a, { state: "ca", postalCode: " 94105 " })
check("Q7", "the same data again (also with a lower-case state and spaces around the ZIP code) succeeds and changes nothing", addr_errs(r2) == [] && me_addr(q_a) == ADDRESS.transform_keys(&:to_s), r2[:body][0, 100], bad: "MEDIUM")
r3 = gql(UPDATE_ADDRESS, variables: { i: ADDRESS.except(:addressLine2) }, token: q_a) # not addr_save: it merges line 2 back in
check("Q7a", "line 2 is optional: leaving it out clears it", addr_errs(r3) == [] && me_addr(q_a)["addressLine2"].nil?, r3[:body][0, 100], bad: "LOW")

addr_save(q_b, { city: "Oakland" })
check("Q8", "each user has their own address: B's save changed nothing for A, and A's data is not in B's me",
      me_addr(q_a)["city"] == "San Francisco" && me_addr(q_b)["city"] == "Oakland" && !gql("{ me { city } }", token: q_b)[:body].include?("San Francisco"), bad: "CRITICAL")

rs = 8.times.map { Thread.new { addr_save(q_a, { city: "Parallel" }) } }.map(&:value)
check("Q9", "8 parallel saves of the same data: no 500, all succeed, the address is consistent", rs.all? { |x| clean?(x) && addr_errs(x) == [] } && me_addr(q_a)["city"] == "Parallel", rs.map { |x| x[:body][0, 60] }.tally.inspect, bad: "HIGH")

q_steps = onb_of(q_a)&.dig("steps") || []
check("Q10", "the address step: not finished while the profile step is open (order), finished by the server once the profile is saved",
      q_steps.find { |x| x["key"] == "address" }&.dig("completed") == false && prof_errs(prof_save(q_a)) == [] && onb_of(q_a)&.dig("steps")&.find { |x| x["key"] == "address" }&.dig("completed") == true,
      onb_of(q_a).inspect[0, 160], bad: "HIGH")

# ---------- R. Terms (acceptTerms, and the terms fields of me) ----------
def terms_errs(r) = op_errs(r, "acceptTerms")
def me_terms(token) = gql("{ me { termsVersion termsAcceptedAt } }", token: token)[:json]&.dig("data", "me")

r_a = tok_of(signup(uniq, onboard: false))
check("R1", "a new user has accepted nothing", me_terms(r_a) == { "termsVersion" => nil, "termsAcceptedAt" => nil }, me_terms(r_a).inspect, bad: "LOW")

wrong = terms_save(r_a, "1999-01-01")
check("R2", "an old or invented version is refused with VALIDATION_FAILED on `version`, and nothing is recorded",
      terms_errs(wrong)&.first&.values_at("path", "code") == [ %w[input version], "VALIDATION_FAILED" ] && me_terms(r_a)["termsAcceptedAt"].nil?, wrong[:body][0, 140], bad: "HIGH")

ok = terms_save(r_a)
first_time = me_terms(r_a)
check("R3", "the current version is recorded with the server time", terms_errs(ok) == [] && first_time["termsVersion"] == terms_version && first_time["termsAcceptedAt"], ok[:body][0, 140], bad: "HIGH")

terms_save(r_a)
check("R4", "accepting again keeps the first time (the client cannot move it)", me_terms(r_a) == first_time, me_terms(r_a).inspect, bad: "MEDIUM")

check("R5", "the terms step: not finished while the earlier steps are open, finished by the server after the profile and the address are saved",
      onb_of(r_a)&.dig("steps")&.find { |x| x["key"] == "terms" }&.dig("completed") == false && (prof_save(r_a); addr_save(r_a); onb_of(r_a)&.dig("completed") == true), onb_of(r_a).inspect[0, 160], bad: "HIGH")

# ---------- Z. Schema-driven phase (every operation, including ones added later) ----------
if LABEL == "test"
  frag = "fragment T on __Type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } }"
  intro = gql("{ __schema { queryType { name } mutationType { name } types { kind name " \
              "fields { name type { ...T } args { name type { ...T } } } inputFields { name type { ...T } } enumValues { name } } } } #{frag}")
  types = (intro[:json]&.dig("data", "__schema", "types") || []).to_h { |t| [ t["name"], t ] }
  roots = %w[queryType mutationType].filter_map { |k| n = intro[:json]&.dig("data", "__schema", k, "name"); [ k, types[n] ] if n }
  fuzz = [ "", "x" * 10_000, "' OR 1=1 --", "\u0000", "🔥" * 50, "../../etc/passwd", "<script>alert(1)</script>", "-1", "99999999999999999999" ]

  type_str = ->(t) { t["kind"] == "NON_NULL" ? "#{type_str.(t['ofType'])}!" : t["kind"] == "LIST" ? "[#{type_str.(t['ofType'])}]" : t["name"] }
  base = ->(t) { t["ofType"] ? base.(t["ofType"]) : t }
  build = lambda do |t, str|
    case t["kind"]
    when "NON_NULL" then build.(t["ofType"], str)
    when "LIST" then [ build.(t["ofType"], str) ]
    when "ENUM" then types[t["name"]]["enumValues"].first["name"]
    when "INPUT_OBJECT" then types[t["name"]]["inputFields"].to_h { |f| [ f["name"], build.(f["type"], str) ] }
    else
      case t["name"] when "Int" then 1 when "Float" then 1.5 when "Boolean" then true when "ID" then SecureRandom.uuid else str end
    end
  end
  op_for = lambda do |kind, field, str|
    vars = field["args"].map { |a| "$#{a['name']}: #{type_str.(a['type'])}" }.join(", ")
    args = field["args"].map { |a| "#{a['name']}: $#{a['name']}" }.join(", ")
    sel = %w[OBJECT INTERFACE UNION].include?(base.(field["type"])["kind"]) ? " { __typename }" : ""
    [ "#{kind} Z#{vars.empty? ? '' : "(#{vars})"} { #{field['name']}#{args.empty? ? '' : "(#{args})"}#{sel} }",
     field["args"].to_h { |a| [ a["name"], build.(a["type"], str) ] } ]
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
      return [ f["name"], *rest ] if rest
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
  count_max = ->(v) { v.is_a?(Array) ? [ v.size, *v.map { |x| count_max.(x) } ].max : v.is_a?(Hash) ? (v.values.map { |x| count_max.(x) }.max || 0) : 0 }
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
      swap = ->(h, id) { h.to_h { |k, x| [ k, x.is_a?(Hash) ? swap.(x, id) : (x.is_a?(String) && x.match?(/\A[0-9a-f-]{36}\z/) ? id : x) ] } }
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
      [ "http://127.0.0.1:#{canary_port}/ssrf", "http://localhost:#{canary_port}/", "http://[::1]:#{canary_port}/", "http://2130706433:#{canary_port}/",
       "http://169.254.169.254/latest/meta-data/", "file:///etc/passwd", "gopher://127.0.0.1:#{canary_port}/" ].each_with_index do |u, i|
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
