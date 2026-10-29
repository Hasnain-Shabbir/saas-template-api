module OnboardingHelpers
  # The steps in the real registry, kept before any example swaps them.
  REAL_STEPS = Onboarding::Registry::STEPS

  def real_onboarding_steps = REAL_STEPS

  # A spec swaps in the steps it needs. `stub_const` puts the original back after each example.
  def stub_onboarding_steps(*steps)
    stub_const("Onboarding::Registry::STEPS", steps.freeze)
  end

  def onboarding_step(key, **options) = Onboarding::Step.new(key:, **options)
end

RSpec.configure do |config|
  config.include OnboardingHelpers

  # The real registry has the profile step, which blocks every member until the profile is saved. Most specs are not about
  # onboarding, so each example starts with no steps. A spec about onboarding puts in the steps it needs (or `real_onboarding_steps`).
  config.before { stub_onboarding_steps }
end
