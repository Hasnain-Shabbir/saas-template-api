# Redis for Sidekiq. The URL comes from the environment, never from code (see .env.example).
# If REDIS_URL is not set, Sidekiq uses its own default (Redis on this machine), which is fine for development only.
redis_config = { url: ENV["REDIS_URL"].presence }.compact

Sidekiq.configure_server { |config| config.redis = redis_config }
Sidekiq.configure_client { |config| config.redis = redis_config }
