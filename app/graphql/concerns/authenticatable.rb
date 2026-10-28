module Authenticatable
  def current_user
    context[:current_user]
  end

  def current_user!
    current_user || raise(Errors.execution_error(Errors::UNAUTHENTICATED))
  end
end
