Rails.application.routes.draw do
  post "/graphql", to: "graphql#execute"

  # GraphQL sandbox: development only. Never mount it in production or test.
  get "/sandbox", to: "sandbox#show" if Rails.env.development?

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Warden needs the :user scope registered. skip: :all adds no routes:
  # sign up, login, and logout are GraphQL mutations only.
  devise_for :users, skip: :all # <-- It skips creating default routes.
end
