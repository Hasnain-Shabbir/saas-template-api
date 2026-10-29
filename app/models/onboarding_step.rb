# A step a user has finished. A step with no row is not done. The list of steps lives in `Onboarding::Registry`.
class OnboardingStep < ApplicationRecord
  belongs_to :user

  validates :step_key, presence: true,
                       length: { maximum: ValidationRules::ONBOARDING_STEP_KEY_MAX_LENGTH },
                       format: { with: ValidationRules::ONBOARDING_STEP_KEY_FORMAT },
                       uniqueness: { scope: :user_id }
  validates :completed_at, presence: true
end
