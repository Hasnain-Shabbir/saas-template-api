module Users
  # Filters the users list for the admin viewer (Layer 3): a role, a created date range, a partial search by email or name, and
  # archived or not. Every filter is optional and a blank one is ignored. Newest first. It returns a relation, so the caller can paginate it.
  class SearchQuery
    # `created_from` and `created_to` are whole days (a Date, or a Time whose day is used), both included.
    # `archived` true lists only archived users. Anything else lists only active ones (archived users are hidden by default).
    # `scope` is the users to list from.
    def self.call(role: nil, created_from: nil, created_to: nil, search: nil, archived: false, scope: User.all)
      scope = archived ? scope.archived : scope.active
      scope = scope.where(role: role.to_s) if role.present?
      scope = scope.where(created_at: created_from.beginning_of_day..) if created_from.present?
      scope = scope.where(created_at: ..created_to.end_of_day) if created_to.present?
      scope = scope.matching(search) if search.present?
      scope.order(created_at: :desc, id: :desc) # the id keeps the order stable between pages
    end
  end
end
