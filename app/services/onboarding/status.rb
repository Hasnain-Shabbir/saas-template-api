module Onboarding
  class Status
    # The onboarding of one user: the steps of their role, in order, which are done, and which is next.
    # Read only. A role with no steps is complete, and costs no query (the onboarding gate calls this on every request).
    def self.call(user:)
      steps = Registry.steps_for(user)
      done = steps.empty? ? {} : user.onboarding_steps.where(step_key: steps.map(&:key)).pluck(:step_key, :completed_at).to_h

      statuses = steps.map { |step| StepStatus.new(key: step.key, completed: done.key?(step.key), completed_at: done[step.key]) }
      current = statuses.find { |status| !status.completed }&.key

      Result.success(Progress.new(steps: statuses, current_step: current, completed: current.nil?))
    end
  end
end
