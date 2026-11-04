module Authenticatable
  # While impersonating this is the target: policies and data see the member the admin is acting as.
  def current_user
    context[:current_user]
  end

  def current_user!
    current_user || raise(Errors.execution_error(Errors::UNAUTHENTICATED))
  end

  # The open impersonation session of this request, or nil.
  def impersonation
    context[:impersonation]
  end

  # The real person behind an impersonated request (the super_admin), or nil.
  def impersonator
    context[:impersonator]
  end

  def impersonating?
    impersonation.present?
  end
end
