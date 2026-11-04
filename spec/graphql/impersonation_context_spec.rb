require "rails_helper"

RSpec.describe "Impersonation tokens in a request", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:admin) { create(:user, :super_admin, email: "admin@example.test") }
  let!(:member) { create(:user, email: "member@example.test") }
  let(:started) { Impersonations::Start.call(impersonator: admin, target: member, reason_category: "support_request").value }
  let(:me) { "{ me { id email } }" }

  def error_code(body) = body.dig("errors", 0, "extensions", "code")

  # The context the controller built for the last request.
  def context_of_request
    captured = nil
    allow(SaasTemplateApiSchema).to receive(:execute).and_wrap_original do |original, *args, **options|
      captured = options[:context]
      original.call(*args, **options)
    end
    yield
    captured
  end

  it "acts as the member: the request sees the target, and the context names the admin" do
    token = started.token
    body = nil

    context = context_of_request { body = gql(me, token:) }

    expect(body.dig("data", "me")).to include("id" => member.id, "email" => member.email)
    expect(context[:current_user]).to eq(member)
    expect(context[:impersonator]).to eq(admin)
    expect(context[:impersonation]).to eq(started.impersonation)
  end

  it "attributes changes to the admin, not to the member" do
    token = started.token
    allow(Audit).to receive(:actor=).and_call_original

    gql(me, token:)

    expect(Audit).to have_received(:actor=).with(admin.id)
    expect(Audit).not_to have_received(:actor=).with(member.id)
  end

  it "leaves a normal login without an impersonator" do
    context = context_of_request { gql(me, token: token_for(member)) }

    expect(context[:current_user]).to eq(member)
    expect(context[:impersonator]).to be_nil
    expect(context[:impersonation]).to be_nil
  end

  it "keeps the admin's own login working as the admin while a session is open" do
    started

    body = gql(me, token: token_for(admin))

    expect(body.dig("data", "me", "id")).to eq(admin.id)
  end

  describe "when the session is over" do
    it "answers UNAUTHENTICATED after stopImpersonation-style ending (token killed)" do
      token = started.token
      Impersonations::Stop.call(impersonation: started.impersonation)

      expect(error_code(gql(me, token:))).to eq("UNAUTHENTICATED")
    end

    it "answers UNAUTHENTICATED after 30 minutes" do
      token = started.token

      travel_to(31.minutes.from_now) { expect(error_code(gql(me, token:))).to eq("UNAUTHENTICATED") }
    end

    it "answers UNAUTHENTICATED, never a plain member login, for a leftover token of an ended session" do
      token = started.token
      Impersonations::Stop.call(impersonation: started.impersonation)
      member.allowlisted_jwts.create!(jti: started.impersonation.jti, exp: 30.minutes.from_now)

      body = gql(me, token:)

      expect(error_code(body)).to eq("UNAUTHENTICATED")
      expect(body["data"]).to be_nil
    end

    it "answers UNAUTHENTICATED when the admin was blocked after the start" do
      token = started.token
      admin.update!(access_revoked_at: Time.current)

      expect(error_code(gql(me, token:))).to eq("UNAUTHENTICATED")
    end

    it "answers UNAUTHENTICATED when a new start replaced the session (second device)" do
      token = started.token
      Impersonations::Start.call(impersonator: admin, target: create(:user), reason_category: "bug_investigation")

      expect(error_code(gql(me, token:))).to eq("UNAUTHENTICATED")
    end
  end

  it "answers UNAUTHENTICATED for a token signed with another key that names a real session" do
    forged = JWT.encode({ "sub" => member.id, "scp" => "user", "aud" => nil, "jti" => started.impersonation.jti, "exp" => 10.minutes.from_now.to_i },
                        "not the secret", "HS256")

    expect(error_code(gql(me, token: forged))).to eq("UNAUTHENTICATED")
  end
end
