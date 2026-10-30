# Only a super_admin may read the read audit log. No GraphQL operation exposes it yet; the admin screens (Layer 3) will ask this policy.
class ReadAuditPolicy < ApplicationPolicy
  def index? = user.present? && user.super_admin?
end
