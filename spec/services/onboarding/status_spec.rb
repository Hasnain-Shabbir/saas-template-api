require "rails_helper"

RSpec.describe Onboarding::Status do
  let(:user) { create(:user) }

  def progress(for_user = user) = described_class.call(user: for_user).value

  def done(key, for_user = user) = for_user.onboarding_steps.create!(step_key: key, completed_at: Time.current)

  def query_count
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  context "with no steps" do
    it "is complete, with no current step" do
      expect(progress).to have_attributes(steps: [], current_step: nil, completed: true)
    end

    it "costs no query" do
      user # create it first
      expect(query_count { progress }).to eq(0)
    end
  end

  context "with steps" do
    before { stub_onboarding_steps(onboarding_step("profile"), onboarding_step("address"), onboarding_step("terms")) }

    it "starts at the first step" do
      expect(progress).to have_attributes(current_step: "profile", completed: false)
      expect(progress.steps.map { |step| [ step.key, step.completed, step.completed_at ] }).to eq([ [ "profile", false, nil ], [ "address", false, nil ], [ "terms", false, nil ] ])
    end

    it "moves on as steps are done, and completes after the last one" do
      done("profile")
      expect(progress).to have_attributes(current_step: "address", completed: false)
      expect(progress.steps.map(&:completed)).to eq([ true, false, false ])

      done("address")
      done("terms")
      expect(progress).to have_attributes(current_step: nil, completed: true)
      expect(progress.steps.map(&:completed)).to all(be(true))
    end

    it "shows when a step was done" do
      time = Time.zone.local(2026, 10, 29, 9, 0, 0)
      user.onboarding_steps.create!(step_key: "profile", completed_at: time)

      expect(progress.steps.first.completed_at).to eq(time)
    end

    it "does not count the steps of another user" do
      done("profile", create(:user))

      expect(progress).to have_attributes(current_step: "profile", completed: false)
    end

    it "ignores a stored step that is no longer in the registry" do
      done("retired")

      expect(progress.steps.map(&:key)).to eq(%w[profile address terms])
      expect(progress.current_step).to eq("profile")
    end

    it "points at an earlier step that was added later, even when a later step is done" do
      done("terms")

      expect(progress).to have_attributes(current_step: "profile", completed: false)
      expect(progress.steps.map(&:completed)).to eq([ false, false, true ])
    end

    it "uses one query for any number of steps" do
      user
      expect(query_count { progress }).to eq(1)
    end
  end

  context "with steps for one role" do
    before { stub_onboarding_steps(onboarding_step("profile"), onboarding_step("billing", roles: %w[super_admin])) }

    it "shows each role only its own steps, and no roles field" do
      expect(progress(create(:user, :member)).steps.map(&:key)).to eq(%w[profile])
      expect(progress(create(:user, :super_admin)).steps.map(&:key)).to eq(%w[profile billing])
      expect(Onboarding::StepStatus.members).to eq(%i[key completed completed_at])
    end

    it "is complete for a role with no steps" do
      stub_onboarding_steps(onboarding_step("billing", roles: %w[super_admin]))

      expect(progress(create(:user, :member))).to have_attributes(completed: true, current_step: nil)
    end
  end
end
