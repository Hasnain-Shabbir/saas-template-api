module Auth
  class SendEmailChangedNoticeJob < ApplicationJob
    queue_as :mailers

    retry_on Net::OpenTimeout, Net::ReadTimeout, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError

    # Safe to run twice: the old address is cleared after the notice is sent, so the second run sends nothing.
    def perform(user_id)
      user = User.find_by(id: user_id)
      return unless user # the user was deleted

      SendEmailChangedNotice.call(user:)
    end
  end
end
