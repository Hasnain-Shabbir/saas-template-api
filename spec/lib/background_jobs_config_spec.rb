require "rails_helper"

RSpec.describe "Background jobs config" do
  it "uses the test adapter in the test environment (no Redis needed)" do
    expect(ActiveJob::Base.queue_adapter).to be_a(ActiveJob::QueueAdapters::TestAdapter)
  end

  it "does not log job arguments" do
    expect(ActiveJob::Base.log_arguments).to be(false)
  end

  it "sends mail through the mailers queue" do
    expect(ActionMailer::Base.deliver_later_queue_name.to_s).to eq("mailers")
  end

  it "has the queue of every job in config/sidekiq.yml" do
    queues = YAML.safe_load(ERB.new(Rails.root.join("config/sidekiq.yml").read).result, permitted_classes: [ Symbol ])[:queues]

    expect(queues.map { |name, _weight| name }).to include("mailers", "default")
  end
end
