module Onboarding
  class Sync
    # Marks the steps the user has finished, from the data the server holds. No client ever says "this step is done": a data service
    # (for example `Profiles::Update`) saves its data and then calls this. Steps go in order: the first step whose condition is not met
    # stops the walk. Calling it again changes nothing (an existing `completed_at` stays). The caller owns the transaction and the row lock.
    def self.call(user:)
      steps = Registry.steps_for(user)
      done = user.onboarding_steps.where(step_key: steps.map(&:key)).pluck(:step_key)

      steps.each do |step|
        next if done.include?(step.key)
        break unless step.satisfied_by?(user)

        user.onboarding_steps.create!(step_key: step.key, completed_at: Time.current)
      end

      Status.call(user:)
    end
  end
end
