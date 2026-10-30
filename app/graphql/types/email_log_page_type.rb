module Types
  class EmailLogPageType < Types::BaseObject
    description "One page of the email log, newest first"

    field :items, [ Types::EmailLogType ], null: false, complexity: Types::BaseField::LIST_COMPLEXITY, description: "The log entries on this page"
    field :page, Integer, null: false, description: "This page number, starting at 1"
    field :per_page, Integer, null: false, description: "How many entries a page holds at most"
    field :total_count, Integer, null: false, description: "How many entries match the filters, over all pages"
    field :total_pages, Integer, null: false, description: "How many pages there are for the filters"
  end
end
