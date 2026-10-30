module Users
  # Filters the users list for the admin viewer (Layer 3): a role, a created date range, and a partial search by email or name.
  # Every filter is optional and a blank one is ignored. Newest first. It returns a relation, so the caller can paginate it.
  class SearchQuery
    # `created_from` and `created_to` are whole days (a Date, or a Time whose day is used), both included.
    # `scope` is where step 2 (archive) can pass the users to list.
    def self.call(role: nil, created_from: nil, created_to: nil, search: nil, scope: User.all)
      scope = scope.where(role: role.to_s) if role.present?
      scope = scope.where(created_at: created_from.beginning_of_day..) if created_from.present?
      scope = scope.where(created_at: ..created_to.end_of_day) if created_to.present?
      scope = scope.matching(search) if search.present?
      scope.order(created_at: :desc, id: :desc) # the id keeps the order stable between pages
    end
  end
end
