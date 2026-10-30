module EmailLogs
  # Runs every day (see config/schedule.yml). It has no arguments, and running it twice is safe.
  class PurgeJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5

    def perform
      Purge.call
    end
  end
end
