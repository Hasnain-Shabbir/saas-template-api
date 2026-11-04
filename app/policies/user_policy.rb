# Today a user may only act on themselves, whatever their role. Rules for acting on other users
# (for example admin or super_admin) are added here when the owner decides them.
class UserPolicy < ApplicationPolicy
  # The admin users list: only a super_admin, and always the whole list (the record is the class, not one user).
  def index? = user.present? && user.super_admin?

  # Archive and unarchive: only a super_admin, and only a member (the record is the user being changed). So a super_admin can
  # archive neither themselves nor another super_admin.
  def archive? = user.present? && user.super_admin? && record.member?

  def unarchive? = archive?

  # Revoke and grant access: only a super_admin, on any role except a super_admin (so never on themselves or another super_admin).
  # Written as "not a super_admin", so a role added later can be revoked without a change here.
  def revoke_access? = user.present? && user.super_admin? && !record.super_admin?

  def grant_access? = revoke_access?

  # Impersonation: only a super_admin may start one. Which member may be impersonated is a rule of `Impersonations::Start`, which
  # answers with a message that says why (a super_admin, an archived or access-revoked user). Ending a session is for whoever holds its token.
  def impersonate? = user.present? && user.super_admin?

  def stop_impersonation? = self?

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
