# Public sign up is off by default (invite only). A spec that needs signUp to work is tagged `:public_sign_up`.
RSpec.configure do |config|
  config.around(:each, :public_sign_up) do |example|
    original = Rails.configuration.x.allow_public_sign_up
    Rails.configuration.x.allow_public_sign_up = true
    example.run
  ensure
    Rails.configuration.x.allow_public_sign_up = original
  end
end
