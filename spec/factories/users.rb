FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.test" }
    password { "correct horse battery" }

    User.roles.each_key do |role|
      trait(role.to_sym) { role { role } }
    end
  end
end
