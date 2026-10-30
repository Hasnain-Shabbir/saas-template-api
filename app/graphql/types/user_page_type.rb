module Types
  class UserPageType < Types::BaseObject
    description "One page of the users list, newest first"

    field :items, [ Types::UserSummaryType ], null: false, complexity: Types::BaseField::LIST_COMPLEXITY, description: "The users on this page"
    field :page, Integer, null: false, description: "This page number, starting at 1"
    field :per_page, Integer, null: false, description: "How many users a page holds at most"
    field :total_count, Integer, null: false, description: "How many users match the filters, over all pages"
    field :total_pages, Integer, null: false, description: "How many pages there are for the filters"
  end
end
