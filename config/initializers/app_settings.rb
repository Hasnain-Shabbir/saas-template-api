# Settings read from the environment, in one place. This file loads before devise.rb (alphabetical order).
# Production must set them. Development and test fall back to a harmless value.
Rails.application.configure do
  config.x.mailer_from = ENV.fetch("MAILER_FROM") do
    Rails.env.production? ? raise(KeyError, "MAILER_FROM is required") : "no-reply@example.test"
  end

  # Where the frontend lives. Links in emails (the invitation) point here. Same variable as the CORS origin.
  config.x.frontend_url = ENV.fetch("FRONTEND_URL") do
    Rails.env.production? ? raise(KeyError, "FRONTEND_URL is required") : "http://localhost:3000"
  end

  # The template is invite only. Public sign up is off unless ALLOW_PUBLIC_SIGN_UP is exactly "true".
  config.x.allow_public_sign_up = ENV["ALLOW_PUBLIC_SIGN_UP"] == "true"
end
