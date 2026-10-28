# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  :code # the one-time code of password reset and email change, sent as a GraphQL variable
]

# GraphQL: credentials written inline in the query text, and variables sent as a JSON string, never reach the log.
# Variables sent as an object are covered by the key filters above. Writes into the value, as ActiveSupport expects.
Rails.application.config.filter_parameters << lambda do |key, value|
  next unless value.is_a?(String)

  inline_values = key == "query" && value.include?('"')
  value.replace("[FILTERED]") if inline_values || key == "variables"
end
