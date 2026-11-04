FactoryBot.define do
  factory :impersonation do
    association :impersonator, factory: [ :user, :super_admin ]
    association :target, factory: :user
    sequence(:jti) { |n| "jti-#{n}" }
    reason_category { "support_request" }
    started_at { Time.current }
    expires_at { started_at + Impersonation::TTL }
  end
end
