module Impersonations
  # Ends every open session in which `user` is the admin or the member, as `ended_by_system`, and kills their tokens. Called where a
  # user's tokens are deleted anyway (archive, access revoke, password reset, email change), so the log says the session ended then,
  # not only that its time ran out later. A session that had already run out is recorded as `expired` (see `Stop`).
  # Ending nothing succeeds.
  class EndAll
    def self.call(user:)
      Impersonation.unended.where(impersonator_id: user.id).or(Impersonation.unended.where(target_id: user.id)).find_each do |session|
        Stop.call(impersonation: session, ended_reason: "ended_by_system")
      end

      Result.success
    end
  end
end
