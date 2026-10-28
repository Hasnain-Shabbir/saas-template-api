# Settings read from the environment, in one place. This file loads before devise.rb (alphabetical order).
# Production must set them. Development and test fall back to a harmless value.
Rails.application.configure do
  config.x.mailer_from = ENV.fetch("MAILER_FROM") do
    Rails.env.production? ? raise(KeyError, "MAILER_FROM is required") : "no-reply@example.test"
  end
end
