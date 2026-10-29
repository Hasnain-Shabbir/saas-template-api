class ApplicationJob < ActiveJob::Base
  # A change made by a job is recorded in the audit log as "system:<job class>", never as the user it happens to concern.
  around_perform { |job, block| Audit.as(Audit.system_actor(job.class.name), &block) }

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
