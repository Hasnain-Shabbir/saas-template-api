module EmailLogs
  class List
    Page = Data.define(:items, :page, :per_page, :total_count, :total_pages)

    # One page of the email log for the admin viewer, filtered by `SearchQuery`. The caller has already been authorized.
    # An out-of-range `page` or `per_page` is brought into range, not refused: a page below 1 is page 1, a size above the maximum is the maximum.
    def self.call(from: nil, to: nil, status: nil, search: nil, page: nil, per_page: nil)
      per_page = (per_page || ValidationRules::PAGE_SIZE_DEFAULT).clamp(1, ValidationRules::PAGE_SIZE_MAX)
      page = [ page.to_i, 1 ].max
      search = search.to_s.strip.first(ValidationRules::EMAIL_MAX_LENGTH)

      scope = SearchQuery.call(from:, to:, status:, search:)
      total_count = scope.count
      items = scope.offset((page - 1) * per_page).limit(per_page).to_a

      Result.success(Page.new(items:, page:, per_page:, total_count:, total_pages: (total_count / per_page.to_f).ceil))
    end
  end
end
