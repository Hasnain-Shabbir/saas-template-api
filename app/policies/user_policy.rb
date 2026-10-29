# Today a user may only act on themselves, whatever their role. Rules for acting on other users
# (for example admin or super_admin) are added here when the owner decides them.
class UserPolicy < ApplicationPolicy
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
