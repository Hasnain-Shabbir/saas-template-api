FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.test" }
    password { "correct horse battery" }
  end
end
