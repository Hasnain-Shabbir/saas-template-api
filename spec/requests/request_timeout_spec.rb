require "rails_helper"

RSpec.describe "Request timeout" do
  it "runs Rack::Timeout with a service limit of at most 30 seconds" do
    entry = Rails.application.config.middleware.find { |middleware| middleware.klass == Rack::Timeout }

    expect(entry).not_to be_nil
    expect(entry.args.first[:service_timeout]).to be_between(1, 30)
  end

  it "answers a timed-out request with 503, not 500" do
    expect(Rails.application.config.action_dispatch.rescue_responses["Rack::Timeout::RequestTimeoutError"]).to eq(:service_unavailable)
  end

  it "makes PostgreSQL cancel a query that runs too long" do
    limit = ActiveRecord::Base.connection.select_value("SHOW statement_timeout")

    expect(limit).to eq("10s")
    expect { ActiveRecord::Base.connection.execute("SELECT pg_sleep(11)") }.to raise_error(ActiveRecord::QueryCanceled)
  end
end
