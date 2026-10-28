# Stops a request that runs too long, so one slow request cannot hold a Puma thread forever.
# Needs a second line of defence in the database (statement_timeout) for queries stuck inside PostgreSQL.
#
# `require: "rack/timeout/base"` in the Gemfile loads the gem without it inserting itself, so we set the limit here.
# The value comes from the environment, with a safe default (seconds).
Rails.application.configure do
  config.middleware.insert_before Rack::Runtime, Rack::Timeout,
                                  service_timeout: ENV.fetch("REQUEST_TIMEOUT_SECONDS", 15).to_i,
                                  wait_timeout: false # waiting in the queue is the load balancer's job, and we are not behind one in dev

  # A timeout answers 503 (try again later), not a bare 500.
  config.action_dispatch.rescue_responses["Rack::Timeout::RequestTimeoutError"] = :service_unavailable
end

# Rack::Timeout logs every request state at INFO (request ids, no parameters). Only keep the errors.
Rack::Timeout::Logger.level = Logger::ERROR
