module Auth
  class SendPasswordResetJob < ApplicationJob
    queue_as :mailers

    retry_on Net::OpenTimeout, Net::ReadTimeout, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError

    # Safe to run twice: inside the resend cooldown the second run sends nothing.
    def perform(user_id)
      user = User.find_by(id: user_id)
      return unless user # unknown email, or the user was deleted

      SendPasswordReset.call(user:)
    end
  end
end
