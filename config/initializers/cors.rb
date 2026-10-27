# Be sure to restart your server when you modify this file.

# Allow the frontend app to call this API from the browser.
# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # One explicit origin from configuration. Never "*".
    origins ENV.fetch("FRONTEND_URL") { Rails.env.production? ? raise(KeyError, "FRONTEND_URL is required") : "http://localhost:3000" }

    # GraphQL needs only POST (and OPTIONS for the browser preflight).
    resource "*",
      headers: :any,
      methods: [ :post, :options ]
  end
end
