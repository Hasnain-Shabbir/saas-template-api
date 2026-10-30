# Today a user may only act on themselves, whatever their role. Rules for acting on other users
# (for example admin or super_admin) are added here when the owner decides them.
class UserPolicy < ApplicationPolicy
  # The admin users list: only a super_admin, and always the whole list (the record is the class, not one user).
  def index? = user.present? && user.super_admin?

  def show? = self?

  def logout? = self?

  def change_email? = self?

  def update_profile? = self?

  def update_address? = self?

  def accept_terms? = self?

  private

  def self?
    user.present? && record == user
  end
end
