class ApplicationController < ActionController::API
  # Until a request is authenticated, any change it makes is by nobody in particular. `GraphqlController` sets the user.
  before_action { Audit.actor = Audit::ANONYMOUS }

  protected

  # paper_trail stores this next to every audit row made during the request (the `request_id` column).
  def info_for_paper_trail = { request_id: request.request_id }
end
