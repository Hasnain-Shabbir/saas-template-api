# Who is making a change. The audit log reads it when a record is saved.
#   a user id           a logged-in request
#   "anonymous"         a request with nobody logged in (sign up, reset password, accept invitation)
#   "system:<label>"    no request at all: a job ("system:Auth::SendPasswordResetJob"), "system:seed", "system:console"
module Audit
  ANONYMOUS = "anonymous".freeze

  # Runs the block with this actor, then puts the old one back (a job, a seed file).
  def self.as(actor, &) = PaperTrail.request(whodunnit: actor, &)

  def self.system_actor(label) = "system:#{label}"

  def self.actor=(actor)
    PaperTrail.request.whodunnit = actor
  end

  def self.fallback_actor
    PaperTrail.request.whodunnit.presence || system_actor(defined?(Rails::Console) ? "console" : "unknown")
  end
end
