# Default deny: every action is false. A policy allows an action by overriding its method.
# `user` is the logged-in user, or nil when nobody is logged in.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index? = false
  def show? = false
  def create? = false
  def update? = false
  def destroy? = false
end
