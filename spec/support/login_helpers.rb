# The two-step login, the way a client does it: `login` emails a code, `verifyLoginCode` trades it for a token.
module LoginHelpers
  include ActiveJob::TestHelper

  LOGIN = <<~GQL.freeze
    mutation($input: LoginInput!) {
      login(input: $input) { success errors { message path code } }
    }
  GQL
  VERIFY_LOGIN_CODE = <<~GQL.freeze
    mutation($input: VerifyLoginCodeInput!) {
      verifyLoginCode(input: $input) { token user { id email role } errors { message path code } }
    }
  GQL

  # Step 1. The job runs now, so the email is delivered.
  def request_login_code(email:, password:)
    perform_enqueued_jobs { gql(LOGIN, variables: { input: { email:, password: } }) }
  end

  # The code only exists in the email (the database keeps a digest), so the tests read it from there, like a user would.
  def login_code_from_email(mails = ActionMailer::Base.deliveries)
    mails.reverse.find { |mail| mail.subject == LoginMailer::SUBJECT }&.text_part&.body&.decoded&.[](/^(\d{6})$/, 1)
  end

  # Step 2.
  def verify_login_code(email:, code:)
    gql(VERIFY_LOGIN_CODE, variables: { input: { email:, code: } })
  end

  # Both steps. Returns the answer of step 2, or the answer of step 1 when it sent no code (so a failure shows).
  def log_in(email:, password:)
    sent_before = ActionMailer::Base.deliveries.size
    first = request_login_code(email:, password:)
    code = login_code_from_email(ActionMailer::Base.deliveries.drop(sent_before))

    code ? verify_login_code(email:, code:) : first
  end

  # A code that is not the one in the email.
  def wrong_login_code(code)
    code == "000000" ? "111111" : "000000"
  end
end

RSpec.configure do |config|
  config.include LoginHelpers, type: :request
end
