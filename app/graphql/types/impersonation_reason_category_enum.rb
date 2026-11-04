module Types
  # Built from Impersonation.reason_categories, so a new category is added in one place (the enum on Impersonation, plus its migration).
  class ImpersonationReasonCategoryEnum < GraphQL::Schema::Enum
    graphql_name "ImpersonationReasonCategory"
    description "Why a super_admin starts an impersonation. The category \"other\" needs a written note"

    Impersonation.reason_categories.each_key do |category|
      value category.upcase, value: category, description: "The reason is: #{category.humanize(capitalize: false)}"
    end
  end
end
