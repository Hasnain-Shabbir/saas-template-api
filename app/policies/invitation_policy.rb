# Only a super_admin deals with invitations, and an invitation can only make a member (an admin is not made by invitation
# for now). The role being granted is part of the rule, so an inviter can never hand out a role they may not grant. For `revoke?` and `resend?` the record is the Invitation class (no single invitation is loaded).
class InvitationPolicy < ApplicationPolicy
  GRANTABLE_ROLES = %w[member].freeze

  def create? = super_admin? && grantable_roles.include?(record.role)

  def revoke? = super_admin?

  def resend? = super_admin?

  # The roles this user may put on an invitation.
  def grantable_roles
    super_admin? ? GRANTABLE_ROLES : []
  end

  private

  def super_admin?
    user.present? && user.super_admin?
  end
end
