module Auth
  class SendEmailChangeCodeJob < ApplicationJob
    queue_as :mailers

    retry_on Net::OpenTimeout, Net::ReadTimeout, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError

    # Safe to run twice: inside the resend cooldown the second run sends nothing.
    # The argument is the user id only. The pending address and the code are read and made inside the service.
    def perform(user_id)
      user = User.find_by(id: user_id)
      return unless user # the user was deleted

      SendEmailChangeCode.call(user:)
    end
  end
end
