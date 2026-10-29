FactoryBot.define do
  factory :invitation do
    sequence(:email) { |n| "invited#{n}@example.test" }
    role { "member" }
    expires_at { Invitation::LIFETIME.from_now }
  end
end
