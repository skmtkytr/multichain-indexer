Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :blocks, only: [:index, :show], param: :number
      resources :transactions, only: [:index, :show], param: :hash
      resources :logs, only: [:index]
      resources :contracts, only: [:index, :show], param: :address

      # Indexer control
      post "indexer/start", to: "indexer#start"
      post "indexer/stop", to: "indexer#stop"
      get  "indexer/status", to: "indexer#status"
    end
  end

  # Dashboard
  root "dashboard#index"

  get "health", to: proc { [200, {}, ["ok"]] }
end
