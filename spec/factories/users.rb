FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.test" }
    password { "correct horse battery" }

    trait :with_profile do
      first_name { "Ada" }
      last_name { "Lovelace" }
      date_of_birth { Date.new(1990, 5, 21) }
      phone { "+14155552671" }
    end

    trait :with_address do
      address_line_1 { "1 Market Street" }
      city { "San Francisco" }
      state { "CA" }
      postal_code { "94105" }
      country { "US" }
    end

    trait :with_terms do
      terms_version { Terms::Current::VERSION }
      terms_accepted_at { Time.current }
    end

    User.roles.each_key do |role|
      trait(role.to_sym) { role { role } }
    end
  end
end
