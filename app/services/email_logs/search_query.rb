module EmailLogs
  # Filters the email log for the admin viewer (Layer 3): a date range, a status, and a partial search by address.
  # Every filter is optional and a blank one is ignored. Newest first. It returns a relation, so the caller can paginate it.
  class SearchQuery
    # `from` and `to` are whole days (a Date, or a Time whose day is used), both included. The date is the row's `created_at`,
    # because a failed row has no `sent_at`.
    def self.call(from: nil, to: nil, status: nil, search: nil, scope: EmailLog.all)
      scope = scope.where(created_at: from.beginning_of_day..) if from.present?
      scope = scope.where(created_at: ..to.end_of_day) if to.present?
      scope = scope.where(status: status.to_s) if status.present?
      scope = scope.recipient_matching(search) if search.present?
      scope.order(created_at: :desc, id: :desc) # the id keeps the order stable between pages
    end
  end
end
