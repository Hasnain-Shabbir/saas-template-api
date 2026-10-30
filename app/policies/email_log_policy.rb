# Only a super_admin may read the email log. It holds the mails as sent, with live codes and links, so this is a narrow rule.
# `index?` is the list, `show?` one entry. Reading the body is also written to the read audit log (see `Types::EmailLogType`).
class EmailLogPolicy < ApplicationPolicy
  def index? = super_admin?

  def show? = super_admin?

  private

  def super_admin?
    user.present? && user.super_admin?
  end
end
