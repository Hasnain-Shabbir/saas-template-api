module EmailLogs
  class Purge
    BATCH_SIZE = 1_000

    # Deletes the rows older than `EmailLog::RETENTION`, in batches so one run never holds a long lock.
    # Safe to run twice: the second run finds nothing. Returns the number of rows deleted.
    def self.call
      Result.success(EmailLog.expired.in_batches(of: BATCH_SIZE).delete_all)
    end
  end
end
