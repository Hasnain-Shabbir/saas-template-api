class ApplicationMailer < ActionMailer::Base
  include EmailLoggable

  default from: -> { Rails.configuration.x.mailer_from }
  layout "mailer"
end
