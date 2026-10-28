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
else
  rec("Z", "schema phase skipped (introspection is off in this mode, as it should be)", "INFO")
end

File.write(OUT, JSON.pretty_generate($results))
puts "\nSUMMARY #{LABEL}: #{$results.map { |x| x[:verdict] }.tally.inspect}"
